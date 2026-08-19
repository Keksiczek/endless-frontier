#!/usr/bin/env python3
"""Whether the things an entry names actually exist.

The other checks read one entry at a time and ask whether it is well formed.
This one asks the question that only the whole repository can answer: a quest
stage that waits for the tech `alchemy` is perfectly shaped JSON, loads without
a murmur, and can never be completed, because no such tech exists. So is a
stage waiting on a world flag nothing in the game ever sets.

Both came out of the very first drafts a model wrote, which passed every other
check — which is the argument for this file existing.

The table below is not declared, it was **measured**: every key here resolves
into its target file for 100% of the values the shipped content uses (the survey
that produced it is a dozen lines of `json.load` and set intersection, and it is
worth re-running if a new kind of reference appears). A key that resolved only
most of the time would not belong here — a check that cries wolf gets switched
off, which is worse than not having it.
"""

from __future__ import annotations

import json

from content_kinds import KINDS, path_for

# key in the JSON  →  the kind whose ids it must name.
REFERENCES: dict[str, str] = {
    "buildingId": "buildings",        # techs: what a tech unlocks
    "neighbor": "buildings",          # buildings: what wants to stand next door
    "requiresBuilding": "buildings",  # recipes: where the work happens
    "requires_building": "buildings",  # meals, conveyances: the older spelling
    "serves_buildings": "buildings",  # motions: the workplace a clip belongs in
    "requires_tech": "techs",          # conveyances: what must be known first
    "itemID": "items",                # quests: what is asked for or handed over
    "outputItemID": "items",          # recipes: what comes out
    "requires": "techs",              # techs: the DAG's edges
    "requiresTech": "techs",          # recipes: what must be known first
    "techResearched": "techs",        # events, quests: a condition on the tree
}

# A world flag is only worth waiting on if something can set it. Four things
# can, and none of them is a JSON file the generator writes into:
#
#   · `biome:…_present` — `GameWorldFactory` / `ExplorationEngine`, from the
#     `world_flag` on each biome, when that country is revealed;
#   · `cleared:…`       — `SiteEngine`, when a site of that region kind is put
#     down, one per `RegionKind`;
#   · `eventcat:…`      — `TechEngine`, for an `unlock_event_category` effect;
#   · anything a `set_world_flag` effect in the content itself writes.
#
# Copied from `Region.swift`. Kept here rather than parsed out of the Swift,
# because a seven-case enum that has not changed in months is cheaper to keep
# honest by hand than a parser is to keep working.
REGION_KINDS = (
    "homeland", "wilderness", "ruins", "dungeon", "anomaly", "sanctuary", "lost_city",
)


def _load(kind: str):
    return json.loads(path_for(kind).read_text(encoding="utf-8"))


def ids_of(kind: str) -> set[str]:
    return {
        entry["id"] for entry in _load(kind)
        if isinstance(entry, dict) and isinstance(entry.get("id"), str)
    }


def _strings(value) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [item for item in value if isinstance(item, str)]
    return []


def _flags_written(node, out: set[str]) -> None:
    if isinstance(node, dict):
        if node.get("type") == "set_world_flag" and isinstance(node.get("flag"), str):
            out.add(node["flag"])
        if node.get("type") == "unlock_event_category" and isinstance(node.get("category"), str):
            out.add(f"eventcat:{node['category']}")
        for value in node.values():
            _flags_written(value, out)
    elif isinstance(node, list):
        for item in node:
            _flags_written(item, out)


def settable_flags(draft=None) -> set[str]:
    """Every flag the running game can ever turn on.

    The draft is folded in, so a batch that sets a flag in one entry and waits
    on it in another is judged as the pair it is rather than as two halves.
    """
    flags = {f"cleared:{kind}" for kind in REGION_KINDS}
    for biome in _load("biomes"):
        flag = biome.get("world_flag")
        if isinstance(flag, str):
            flags.add(flag)
    for kind in KINDS:
        _flags_written(_load(kind), flags)
    if draft is not None:
        _flags_written(draft, flags)
    return flags


# Keys whose *dictionary keys* are ids, rather than their values. A recipe's
# `materials` is `{item_id: count}`, so everything above walks straight past it
# — which is how six recipes shipped asking for `flint`, an item that does not
# exist, and for a stone mortar, an item that exists and is a tool rather than
# something you use up.
REFERENCE_MAPS: dict[str, str] = {
    "materials": "items",     # recipes: what is consumed
    "ingredients": "items",   # meals: the same idea, different word
}


def dangling(draft, out: list[str], known_ids: dict[str, set[str]],
             flags: set[str]) -> None:
    if isinstance(draft, dict):
        for key, value in draft.items():
            target = REFERENCE_MAPS.get(key)
            if target and isinstance(value, dict):
                for name in value:
                    if name not in known_ids[target]:
                        out.append(f"{key}[{name}] — no such {target[:-1]}")
        for key, value in draft.items():
            target = REFERENCES.get(key)
            if target:
                for name in _strings(value):
                    if name not in known_ids[target]:
                        out.append(f"{key}={name} — no such {target[:-1]}")
            if key == "worldFlag":
                for name in _strings(value):
                    if name not in flags:
                        out.append(f"worldFlag={name} — nothing in the game sets it")
            if not isinstance(value, str):
                dangling(value, out, known_ids, flags)
    elif isinstance(draft, list):
        for item in draft:
            dangling(item, out, known_ids, flags)


def check(draft, kind: str) -> list[str]:
    """Every name in the draft that points at nothing."""
    known_ids = {target: ids_of(target)
                 for target in set(REFERENCES.values()) | set(REFERENCE_MAPS.values())}
    # A draft may refer to itself — two techs in one batch where the second
    # needs the first is a good draft, not a broken one. Only into its own
    # kind, though: a draft of quests does not make new techs exist.
    if kind in known_ids and isinstance(draft, list):
        known_ids[kind] |= {
            entry["id"] for entry in draft
            if isinstance(entry, dict) and isinstance(entry.get("id"), str)
        }

    faults: list[str] = []
    dangling(draft, faults, known_ids, settable_flags(draft))
    return sorted(set(faults))
