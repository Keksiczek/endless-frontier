# The 2.5D layer — height, shadow, and a building you can name

<!-- Written 2026-08-27. A specification and a plan, not a report of work done.
     Nothing in here is built yet; §6 is the order I would build it in. -->

Two complaints, one cause. *"Chci, aby byly zpracované mapy, osady, budovy — a
každá unikátní a graficky rozeznatelná, až na nutné výjimky."* And the canvas
reads flat: a town is a set of marks lying on the ground, not a place with
things standing up in it.

Both come from the same gap. **The renderer has no height axis.** A building is
a rectangle on the footprint with courses ruled across it and a roof glyph drawn
*inside the same rectangle*; a tree is a crown at its own coordinate; a colonist
is a figure at theirs. Everything is at z = 0 and depth is faked by draw order
alone. There is no surface facing the viewer for a material to be made of, no
shadow whose length means anything, and — because the only way to tell two
buildings apart is the plan view — no room for the sixty-two of them to look
like sixty-two different things.

This is the specification for the layer that fixes both.

---

## 1. What is there now, measured

Counted 2026-08-27 against `buildings.json` and `SettlementRendererLayout`:

| | |
|---|---|
| Buildings | 62 |
| Distinct `look` values | 30 |
| Buildings that share their `look` with another | **51** |
| Buildings whose `look` is theirs alone | 11 |
| Buildings `StructureVariant`'s axes cannot tell apart | **0** |

The last row is the important one and it is easy to misread. The *signature*
already separates all sixty-two — `look`, era, footprint, workers, housing,
production, defence and pollution give no collisions at all. So this is not a
data problem and there is nothing to disambiguate: **the drawing simply does not
spend the difference it is handed.** `factory`, `vehicle_works`,
`assembly_plant`, `automated_factory` and `garage` are five buildings sharing
`look: plant`, and what separates them on screen is a bay count and a chimney.

That is the shape of rule 92 (composition, not more shapes) left half-finished.
`StructureVariant` was the right move and it derives too few axes to be seen.

## 2. The projection

**A lift, not a rotation.** The map stays in plan — the grid, the footprints,
the walking, the fog and every hit test keep the coordinates they have, and no
engine changes. What is added is one vertical offset applied at draw time:

```
screen(p, h) = (point(p, rect).x,
                point(p, rect).y - h * liftPerUnit * zoom)
```

`h` is a height in **map units** — the same units `LocalPoint` is in, so a thing
one grid tile tall has the height of one grid tile and nobody has to convert.
`liftPerUnit` is the single constant that decides how steep the world looks; one
number, in `SettlementRenderer`, next to `Camera`.

Three consequences worth stating, because each of them is a thing that will
otherwise be discovered by drawing it wrong:

- **A footprint is drawn twice.** Once on the ground where it belongs, and once
  lifted, as the top of the walls. The quadrilateral between the two is the wall
  face — the surface that did not exist before, and the whole reason a fabric
  can be *seen* rather than ruled across a plan.
- **Only the near faces are drawn.** The lift is straight up, so the visible
  walls are the south face and whichever of east/west the sun is not behind.
  Two quads, never four.
- **The lift must not move the hit test.** A tap is on the ground the thing
  stands on (rule 5's sibling: the drawing may read the simulation's positions
  and must not become one). Selecting a tall building by its roof is a nicety
  and comes later, if at all.

## 3. The layers

Painter's algorithm, and the point of naming them is that each is a pass with
one job and a rule about what may write into it. Today's `SettlementRenderer.draw`
is already close to this; the change is that layers 4–7 gain a height.

| # | Layer | What it draws | May read |
|---|---|---|---|
| 0 | ground | tiles, tracks, zones, water | `LocalMap`, `ColonyMap` |
| 1 | ground clutter | crops, piles, marks, blood | the settlement |
| 2 | **shadow** | every standing thing's silhouette, offset by the sun | layers 3–6's own geometry |
| 3 | footings | the footprint quad, the plinth, the yard | `ColonyMap.Placement` |
| 4 | **body** | the lifted wall faces and their fabric | `StructureVariant` |
| 5 | **roof** | the closing form, drawn on top of the walls | `StructureVariant.roofline` |
| 6 | **rooftop** | what stands on the roof — vents, aerials, tanks | `StructureVariant.rooftop` |
| 7 | attachments | what stands *beside* it and names it (§4) | `structures.json` |
| 8 | agents | colonists, animals, raiders, carts | `AgentMotion` |
| 9 | weather & night | fog, wash, lamps | the clock |

**Depth sort runs across layers 3–8 together**, on the *foot* of each thing —
its ground y — so a colonist walking in front of a granary is in front of it and
one walking behind is behind. This is the part that cannot be bolted on later:
if buildings are drawn as a block and agents as a block, a tall building will
always cover somebody standing in front of it. One sorted pass, or the illusion
does not hold.

**The shadow comes from the sun that is already there.** `SettlementLight.sun`
gives a direction and an elevation; a shadow is the standing silhouette
projected along it, its length `h / tan(elevation)`. That is rule 35 — a number
that must agree with another number should *be* it. A shadow with its own angle
constant is a shadow that will drift out of step with the light by lunchtime.

## 4. Sixty-two buildings you can name

The vocabulary, not more code. A building is a **composition of parts the
renderer already knows how to draw**, and the difference between a bloomery and
a foundry is which parts and how many — not a new routine per building.

The bank is `GameData/structures.json`, one entry per building id, and each
entry is a recipe rather than a picture:

```json
{
  "id": "bloomery",
  "standing": 1.4,
  "roof": "gable",
  "fabric": "stone",
  "trim": "timber",
  "rooftop": "vents",
  "attachments": ["charcoal_heap", "bellows", "ore_pile"],
  "yard": "beaten_earth",
  "accent": "ember"
}
```

- `standing` — the wall height in map units, before the roof. This is the
  number that makes a longhouse low and a watchtower tall, and it is the one
  thing the plan view could never say.
- `roof` — the closed set `StructureVariant.Roofline` already has: `gable`,
  `sawtooth`, `flat`, `barrel`, `stepped`.
- `fabric`, `trim` — what the wall face and its framing are made of.
  `Cover.Substance` (`wood`, `stone`, `foliage`) is the existing vocabulary and
  is too coarse for sixty-two buildings; the specification adds `thatch`,
  `daub`, `brick`, `panel`, `glass`, `sheet` and keeps the mapping to
  `Cover.Substance` for the sim, so **cover is unchanged** — a brick wall stops
  a shaft exactly as a stone one does.
- `attachments` — **the field that does the work.** What stands beside the
  building and tells you what it is from across the valley: a charcoal heap, a
  timber stack, drying racks, a cart under an awning, an anvil, a well head,
  crates on a loading step, a bell frame, a hitching rail. This is where the
  five `plant` buildings stop being one building drawn five times.
- `yard` — what the ground does around it: beaten earth, gravel, cobbles,
  planking, nothing.
- `accent` — one colour that is allowed to be warm. Almost everything in this
  world is bone hairline on slate; a forge has an ember, a lab has a cold
  green, a market has an awning. **One per building at most**, or the town
  becomes a fairground.

The exceptions the user allowed for are real and should be written down rather
than discovered: **a wall is a wall**, and `palisade`, `stone_walls` and any
later curtain are meant to read as the same thing at different tiers. The same
goes for `farm_basic` and `farm_advanced`. Everything else gets its own
silhouette.

### What makes a composition good

- It is legible **at the opening zoom**, before labels turn on at 1.6. If the
  only difference is a mark two pixels wide, the difference is not there.
- It says what the building *does*, not what it is called. A player who has
  never read the name should be able to guess the trade.
- It is honest about the age. A medieval workshop and a modern assembly plant
  differ in fabric and roof before they differ in ornament.

## 5. The texture pass

Two surfaces, and only one of them exists today.

**Horizontal** — `ground.json`'s `texture` and `texture_alpha`, drawn by
`SettlementGround`. Twenty grounds across eleven marks (`stipple` ×4,
`pebbles` ×3, `blades` ×2, `glint` ×2, `chips` ×2, `driedCrack` ×2, and one each
of `ripples`, `crack`, `reed`, `sprig`, `frond`). This is *worked*, and the
revision wanted here is a review rather than a rewrite: four grounds sharing
`stipple` is four grounds that look the same underfoot.

**Vertical** — the wall faces §2 creates, which nothing has ever had to fill.
`SettlementStructures.fabricLines` is the seed of it and knows three substances:
log courses for `wood`, offset coursed blocks for `stone`, a woven weave for
`foliage`. Every fabric §4 adds needs its own: thatch is combed straight lines
under a thick eave, daub is smooth with a timber frame across it, brick is
finer courses than stone, panel is a grid of joints, glass is verticals and one
horizontal transom, sheet is corrugation.

Both banks are a good size for a model and a bad size for a person: twenty
grounds and a dozen fabrics is an afternoon of fiddling and a morning of
arguing about it. §6 puts them through the generator.

## 6. The order I would build it in

Each step is separately shippable and separately measurable, which is rule 72 —
one change per measurement.

1. **The lift and the shadow, no data.** `liftPerUnit`, the two wall quads, the
   sun-derived shadow, and every building at a `standing` derived from
   `storeys`. Nothing new in `GameData`. This is the step that either looks
   right or does not, and it is cheap to abandon.
2. **The single depth-sorted pass** across footings, bodies, attachments and
   agents. Without this the first step is a lie the moment anybody walks.
3. **`structures.json` with the vocabulary and a dozen hand-written entries** —
   enough for the generator to learn the shape from, and enough to see whether
   the parts are the right parts.
4. **The remaining fifty entries by generator** (`Tools/generate.py draft
   structures`), checked and merged like any other bank.
5. **The fabric pass** — one drawing routine per fabric, and the vertical
   textures of §5.
6. **The ground revision** (`Tools/revise.py ground`), last, because it is the
   one that changes what is already right.

## 7. The seed

`Tools/drafts/` is gitignored — it holds what the generator produces — so the
hand-written exemplars live here, where they are read beside the specification
they belong to. **Eighteen entries, chosen to span the axes** rather than to be
the eighteen most important buildings: an open-sided lean-to and a glass block,
a turf mound and a sawtooth shed, something with an ember and something with
nothing warm at all. That is what the generator learns the shape from.

The schema is `docs/data-schemas/structures.json`, and it is the authority on
the closed sets.

```json
[
  {
    "id": "hut",
    "standing": 0.9,
    "roof": "gable",
    "fabric": "daub",
    "trim": "timber",
    "rooftop": "none",
    "attachments": [
      "woodpile",
      "wash_line"
    ],
    "yard": "beaten_earth",
    "accent": "hearth"
  },
  {
    "id": "longhouse",
    "standing": 1.1,
    "roof": "gable",
    "fabric": "timber",
    "trim": "timber",
    "rooftop": "vents",
    "attachments": [
      "woodpile",
      "bench",
      "hitching_rail"
    ],
    "yard": "beaten_earth",
    "accent": "hearth"
  },
  {
    "id": "work_shelter",
    "standing": 0.8,
    "roof": "gable",
    "fabric": "open",
    "trim": "timber",
    "rooftop": "none",
    "attachments": [
      "work_block",
      "tool_rack",
      "timber_stack"
    ],
    "yard": "beaten_earth",
    "accent": "none"
  },
  {
    "id": "workshop",
    "standing": 1.6,
    "roof": "gable",
    "fabric": "timber",
    "trim": "stone",
    "rooftop": "vents",
    "attachments": [
      "anvil",
      "tool_rack",
      "crates"
    ],
    "yard": "cobbles",
    "accent": "none"
  },
  {
    "id": "wainwright",
    "standing": 1.4,
    "roof": "gable",
    "fabric": "timber",
    "trim": "timber",
    "rooftop": "none",
    "attachments": [
      "cart_under_awning",
      "wheel_rack",
      "timber_stack"
    ],
    "yard": "beaten_earth",
    "accent": "none"
  },
  {
    "id": "bloomery",
    "standing": 1.4,
    "roof": "gable",
    "fabric": "stone",
    "trim": "timber",
    "rooftop": "vents",
    "attachments": [
      "charcoal_heap",
      "bellows",
      "ore_pile"
    ],
    "yard": "beaten_earth",
    "accent": "ember"
  },
  {
    "id": "charcoal_kiln",
    "standing": 1.0,
    "roof": "stepped",
    "fabric": "daub",
    "trim": "none",
    "rooftop": "vents",
    "attachments": [
      "turf_mound",
      "timber_stack"
    ],
    "yard": "beaten_earth",
    "accent": "ember"
  },
  {
    "id": "foundry",
    "standing": 2.6,
    "roof": "sawtooth",
    "fabric": "brick",
    "trim": "sheet",
    "rooftop": "vents",
    "attachments": [
      "slag_heap",
      "crane",
      "ore_pile"
    ],
    "yard": "cobbles",
    "accent": "ember"
  },
  {
    "id": "cookhouse",
    "standing": 1.2,
    "roof": "gable",
    "fabric": "daub",
    "trim": "timber",
    "rooftop": "vents",
    "attachments": [
      "long_table",
      "water_butt",
      "woodpile"
    ],
    "yard": "beaten_earth",
    "accent": "hearth"
  },
  {
    "id": "hunters_lodge",
    "standing": 1.1,
    "roof": "gable",
    "fabric": "timber",
    "trim": "timber",
    "rooftop": "none",
    "attachments": [
      "drying_racks",
      "antler_mount",
      "hitching_rail"
    ],
    "yard": "beaten_earth",
    "accent": "none"
  },
  {
    "id": "lumberyard",
    "standing": 1.0,
    "roof": "flat",
    "fabric": "open",
    "trim": "timber",
    "rooftop": "none",
    "attachments": [
      "saw_frame",
      "timber_stack",
      "sawdust_pile"
    ],
    "yard": "planking",
    "accent": "none"
  },
  {
    "id": "granary",
    "standing": 1.8,
    "roof": "gable",
    "fabric": "timber",
    "trim": "stone",
    "rooftop": "none",
    "attachments": [
      "raised_floor",
      "sack_stack",
      "loading_step"
    ],
    "yard": "gravel",
    "accent": "none"
  },
  {
    "id": "warehouse",
    "standing": 2.2,
    "roof": "barrel",
    "fabric": "brick",
    "trim": "sheet",
    "rooftop": "none",
    "attachments": [
      "loading_step",
      "crates",
      "crane"
    ],
    "yard": "cobbles",
    "accent": "none"
  },
  {
    "id": "watchtower",
    "standing": 3.4,
    "roof": "flat",
    "fabric": "timber",
    "trim": "stone",
    "rooftop": "aerial",
    "attachments": [
      "ladder",
      "brazier"
    ],
    "yard": "gravel",
    "accent": "ember"
  },
  {
    "id": "market",
    "standing": 1.0,
    "roof": "flat",
    "fabric": "open",
    "trim": "timber",
    "rooftop": "none",
    "attachments": [
      "awning_row",
      "crates",
      "scales"
    ],
    "yard": "cobbles",
    "accent": "awning"
  },
  {
    "id": "factory",
    "standing": 3.0,
    "roof": "sawtooth",
    "fabric": "brick",
    "trim": "sheet",
    "rooftop": "vents",
    "attachments": [
      "chimney_bank",
      "coal_heap",
      "loading_step"
    ],
    "yard": "cobbles",
    "accent": "ember"
  },
  {
    "id": "vehicle_works",
    "standing": 2.8,
    "roof": "barrel",
    "fabric": "sheet",
    "trim": "panel",
    "rooftop": "none",
    "attachments": [
      "wide_door",
      "vehicle_apron",
      "tyre_stack"
    ],
    "yard": "cobbles",
    "accent": "none"
  },
  {
    "id": "electronics_lab",
    "standing": 2.4,
    "roof": "flat",
    "fabric": "glass",
    "trim": "panel",
    "rooftop": "aerial",
    "attachments": [
      "cable_run",
      "cooling_fins"
    ],
    "yard": "gravel",
    "accent": "cold_green"
  }
]
```

Two of these are worth reading against each other, because they are the case the
whole bank exists for. `bloomery` and `foundry` are both `look: forge` and both
smelt: stone walls under a gable with a charcoal heap and a pair of bellows
beside them, against a brick sawtooth shed two and a half times as tall with a
slag heap and a crane. Nothing about that needed a new drawing routine, and
nobody has to read a label.

## 8. What must not happen

- **No bitmaps.** This is a vector line-art world at every zoom, and a texture
  atlas would resample to mush the first time somebody pinched (the same reason
  `Camera` scales the rect rather than applying a `scaleEffect`).
- **No height in the simulation.** `standing` is a drawing number. Cover already
  has `Cover.Stature` and it is the sim's own answer to "how much of you is
  behind this"; the two must not be conflated, and a taller drawing must never
  change a fight.
- **No new drawing routine per building.** Rule 92. If a composition cannot say
  it, add a *part*, and every other building gets the part too.
- **No bank without a reader.** `texture` in `ground.json` was validated,
  generated and read by nothing for weeks (rule 47). `structures.json` gets its
  reader in the same change that creates it, or it does not get created.
