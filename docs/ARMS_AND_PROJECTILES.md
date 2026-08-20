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

## What is still owed

1. **Ammunition.** A gun with no rounds is a club; nothing consumes anything
   when it fires. `ammo: "item_id"` on the combat block, spent by
   `SiegeEngine.loose`, is the mechanic — and until it exists, do not generate
   ammunition items, because they would be things nothing consumes (rule 47).
2. **A weapon in the hand.** `SettlementFigures.Armament` is `bow | blade |
   none`, so eighty-two weapons are drawn as three. The fix is the one
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
