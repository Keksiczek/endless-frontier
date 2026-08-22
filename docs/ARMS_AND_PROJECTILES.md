# Arms and what they throw

<!-- Written 2026-08-19, with the projectile layer built and the first
     twenty-four weapons generated on top of it. Read `RULES.md` first;
     rules 47–60 are why this document is shaped the way it is. -->

## The one idea

**A weapon is what it throws.** Fifty-eight weapons shipped with a `class`
(`melee` or `ranged`) and a `damage`, which made a sling, a longbow, a musket
and a marksman's rifle one object with four different numbers on it. The canvas
had nothing else to read, so it drew all of them the same way: six bone-coloured
shafts, fixed spread, one line width, whatever had been fired.

Keks: *"at ma kazda zbran unikat, pistol strili mensi nez sniper."*

So the shot became a thing with a kind, and everything else is derived from it —
how far it carries, how big it draws, how many leave the weapon, what it leaves
behind, and whether it goes off when it arrives.

## The data

```jsonc
{
  "id": "long_range_sniper_rifle",
  "slot": "equipment",
  "equipSlot": "weapon",
  "combat": {
    "class": "ranged",
    "damage": 30,
    "projectile": "bullet",   // what leaves it
    "range": 0.6,             // fraction of the local map
    "caliber": 0.55,          // how big it draws, against an arrow at 1
    "shots": 1,               // how many per beat
    "spread": 0.004,          // optional; how wide it throws
    "blast": 0.05             // only for shell / grenade / rocket
  }
}
```

`ProjectileKind` (`Models/Item.swift`) is the closed list, and it is closed on
purpose — a new kind is a new drawing in `SettlementProjectiles`, which is Swift:

| kind | what it is | arcs | bursts |
|---|---|---|---|
| `none` | melee; nothing leaves the hand | | |
| `arrow` | a shaft from a bow | ✓ | |
| `bolt` | shorter, heavier, flatter — a crossbow | | |
| `stone` | a sling, or a thrown rock | ✓ | |
| `dart` | a blowpipe, and anything small and slow | | |
| `ball` | lead out of a smoothbore, in a great deal of smoke | | |
| `bullet` | rifled: small, fast, mostly a streak | | |
| `shot` | a cone of pellets from one barrel | | |
| `shell` | artillery — it arcs and goes off where it lands | ✓ | ✓ |
| `grenade` | thrown, arcs high, goes off after it stops | ✓ | ✓ |
| `rocket` | carries its own fire, trails smoke, bursts | | ✓ |
| `beam` | no flight at all: a line drawn for an instant | | |

### The numbers that make one weapon not another

`range` is the whole pistol-and-sniper difference and the first thing about a
ranged weapon that was ever anything but damage. What ships now:

| | range | caliber | shots |
|---|---|---|---|
| thrown stone | 0.07 | 0.9 | 1 |
| sling | 0.10–0.14 | 0.8–1.0 | 1 |
| hunting bow | 0.16 | 1.0 | 1 |
| crossbow | 0.19 | 1.1 | 1 |
| longbow | 0.22 | 1.15 | 1 |
| musket | 0.26–0.28 | 1.4–1.5 | 1 |
| blunderbuss / shotgun | 0.12–0.15 | 0.2–0.4 | 8 |
| pistol | 0.14 | 0.4 | 1 |
| submachine gun | 0.18–0.20 | 0.30–0.35 | 3–4 |
| service rifle | 0.35 | 0.45 | 3 |
| marksman's rifle | 0.42 | 0.5 | 1 |
| sniper's rifle | 0.6 | 0.55 | 1 |
| gauss rifle | 0.65 | 0.4 | 1 |
| plasma | 0.62–0.65 | 0.6 | 1 |

`damage` is the weapon **as a whole**, not one pellet: `CombatEngine.militia`
adds it once per fighter and `shots` is how the beat is *drawn*. A shotgun
written as 4 (per pellet) was worth less than a flint knife, and a sniper's
rifle written as 85 was worth five iron swords. The ladder the game actually
has runs 1–5 for stone, 10–15 for iron, 16–22 for powder, 22–30 for modern and
30–42 for near-future.

## Where each field is read

Rule 47 in one table. **A field nothing reads is content that loads and does
nothing** — this is the check to repeat before adding any more.

| field | read by | what it does |
|---|---|---|
| `class` | `CombatEngine.militia` | melee or ranged share of the line |
| `damage` | `CombatEngine.militia`, `weaponProfile` | how hard it hits |
| `projectile` | `SiegeEngine.loose` → `BattleMoment.projectile` → `SettlementProjectiles.draw` | what is drawn crossing the ground |
| `range` | `SiegeEngine.loose` | **who may shoot at whom**, per weapon, instead of one `bowRange` for everybody |
| `caliber` | `BattleMoment.caliber` → the drawing | how big the shot is |
| `shots` | `SiegeEngine.loose` (summed across the archers who fired that kind) | how many are in the air |
| `spread` | `SettlementProjectiles.spreadOf` | how wide the fan goes |
| `blast` | `ProjectileKind.bursts` → the drawing | the ring where it lands |

`spread` and `blast` are the two that are **presentation-only today**. They are
drawn and they do not yet decide a hit — that is the next slice, and until it
lands they should not be tuned as though they were.

## What a fight is actually made of, measured

`ZZBattleDiag` (`EF_DIAG=1`), against a real colony of 68 with 28 on the line:

```
raiders  line armed | steps  ran   secs | ended on       | volleys  kinds        | wounds
      4    28    16 |    20    4      6 | warband broken |       4  arrow,stone  |      0
     25    28    16 |    23   10     14 | warband broken |      10  arrow,stone  |      0
     60    28    16 |    33   27     38 | warband broken |      34  arrow,stone  |      2
     120   28    16 |    43   43     60 | clock ran out  |      80  arrow,stone  |     20
```

Three complaints, three different faults, and they had to be measured apart:

**"It did not last as long as it should."** A raid ran between **seven and
thirty-six seconds** end to end. `Siege.stepsTotal` was 24 at twelve attackers
and a step is 1.4 real seconds while somebody is watching. It is 40 now, and —
more importantly — the clock stopped being the referee: `isFinished` ends on the
**rout** (`Siege.routAtShare`), and only falls back on the clock for a stalemate.

**"The salvos are always the same animation."** They were: `armed 17 of 68 —
["none": 13, "arrow": 4]`, and `kinds on the shelf: []`. Four colonists in the
whole colony carried something that shoots and all four carried a bow, so every
volley in the game was arrows however many weapons the book holds. That is not a
drawing fault — `SettlementProjectiles` composes eleven kinds — it is that
nothing ranged is ever *made*.

**"The fighting is not very dynamic."** `loose` filtered on `side == .colony`,
so **the raiders had no ranged attack at all**: every fight in the game was the
colony shooting at people walking toward it. `returnFire` is the other half, and
what a warband carries comes from the age it is fighting in (`raiderArms`), so a
raid in the age of powder does not look like a raid in the age of bows.

### And what the fight now writes down

`BattleMoment` carries `part` and `wound`, so a beat is "a stab to Mara's left
arm" rather than a name and a number. The anatomy was already there — `Body` has
had head, torso, two arms and two legs, each with its own condition and its own
`missing`, since the animals got it, and `condition <= 0` already takes a limb —
but nothing recorded *where*, and `MedicineEngine.wound` did not say. It says
now (`wounded`), and the wound kind comes from the weapon (`WoundKind.from`)
rather than from a die: a blade cuts, an arrow stabs, a ball bruises, a shell
burns.

### Two faults the lengthening exposed

- **A holding line leaked.** `shoulder` parts bodies without caring which side
  they are on, so a raider could be squeezed *through* an intact line; and
  `isInside` is a circle of `wallReach` while the watch forms up at
  `formUpReach`, **inside** it, so the back rank of a well-manned line stood in
  the same circle as the stores. Measured: a town of sixty held its line, lost
  nobody and was plundered, while a town of ten — too thin to have a back rank —
  lost nothing. Defending made the sack worse. Getting at the stores means
  getting past everybody still standing (`holdTheLine`).
- **A broken line used to end the fight**, which meant losing protected the
  grain. It does not any more: they have the run of the place and they stay for
  it.

### Why nothing but bows was ever in anybody's hands

`armed 17 of 68 — ["none": 13, "arrow": 4]`, and the shelf empty. Three separate
faults stacked, and the first two are the same shape as the council's:

1. **`CombatEngine.weaponProfile` threw the weapon away.** It rebuilt a
   two-field `CombatProfile` — damage and class — and dropped `projectile`,
   `range`, `caliber`, `shots` and `blast` on the floor. The one query that asks
   "what is this colonist holding" could only answer "something ranged" or
   "something melee", which is why eighty-two weapons were drawn as three
   silhouettes: the drawing had nothing else to go on. Rule 47's other face — a
   *reader* that drops the fields is how a live field becomes dead content.
2. **`bestGear` ranks by `worth`, and `worth` is damage.** A bow has less of it
   than an axe, every time, so the quartermaster made blades and only blades.
   `rangedShare` keeps two in five of an armed line able to shoot; the militia
   has counted melee and ranged separately since it was written.
3. **A standing order held its bench for ever.** `workableBenches` sorts
   oldest-first and takes one order per shop — and a standing order never
   finishes. The builders' standing orders for timber and brick were older than
   every batch of spears, so the gear bench was never reached. An order with an
   *end* takes the bench first now; the trickle takes what is left.

Measured across the same fifty years, with nothing else changed:

| | before | after |
|---|---|---|
| armed | 17 of 68 | **49 of 69** |
| on the line | 16 | **27** |
| carrying something ranged | 4 | **17** |
| kinds in hand | `arrow` | `arrow, stone, none` |

### Still short, and not the combat system's fault

A band of four against twenty-eight armed defenders is over in six seconds, and
should be. `BanditEngine` sizes a warband off `temptation` — how full the stores
are — and never off what it would have to fight. See `docs/COUNCIL.md` for the
shape of that argument and `DangerProbe` for the instrument.

## What is still owed

1. **Ammunition.** A gun with no rounds is a club; nothing consumes anything
   when it fires. `ammo: "item_id"` on the combat block, spent by
   `SiegeEngine.loose`, is the mechanic — and until it exists, do not generate
   ammunition items, because they would be things nothing consumes (rule 47).
2. **A weapon in the hand.** `SettlementFigures.Armament` is `bow | blade |
   none`, so eighty-two weapons are drawn as three. Keks: *"vsichni by meli mit
   svou vyzbroj viditelnou pokud nejakou maji."* The fix is the one
   `SettlementConveyances` uses: compose the silhouette from length, barrel,
   stock and what it is made of, driven by `projectile` and the era, rather
   than one drawing per weapon.
3. **Blast doing something.** A grenade that draws a ring and hurts exactly one
   raider is a picture of a grenade.
4. **The hunt.** `HuntEngine` does not read `range` — a hunter with a rifle
   closes to bow distance.

## What may be generated now

Everything below reaches something that reads it:

- **more weapons**, in any era, provided each states a `projectile` and a
  `range` that is not another weapon's. The generator knows the fields
  (`Tools/content_kinds.py`, `items`), and the checker knows the enum.
- **recipes for them** — and this is not optional. 135 pieces of gear once
  shipped obtainable only out of a ruin, because writing the thing and writing
  the way to get it were two jobs and only the first got done. The loop in
  `scratchpad/recipes_loop.py` recomputes what has no recipe each round from
  the two banks, which is the shape to copy.
- **events about arms** — a gun that bursts, a shipment that never came, the
  first shot fired in the valley.

What may **not** be generated yet: ammunition, and anything whose only effect
would be through `blast` or `spread`.
