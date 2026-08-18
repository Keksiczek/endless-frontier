#!/usr/bin/env python3
"""Whether a number sits in the world the other numbers live in.

The checks either side of this one ask whether an entry is *well formed*. This
one asks whether it is *balanced*, which is the only question a model gets
quietly wrong at volume. A workshop that costs 500 materials in the first era
is spelled correctly, points at real things, reads well in both languages, and
ruins the game. At twenty entries you notice. At two hundred you do not, and
the damage is spread thin enough that it looks like the balance was always bad.

**No threshold is written down here.** The range comes out of the content that
already ships, because a constant would be a lie within a month — and because
the constant would have to be wrong for at least one era. Measured, before this
file existed:

    cost.materials across every era   4 – 500   (×125)
    cost.materials within one era               (×1 – ×8)

So era is the dividing line. Judged against the whole file, a 240-material
building is unremarkable; judged against the six other `early_settlement`
buildings, which cost between 4 and 30, it is the bug. Kinds with no era are
judged against the whole file, which is the same rule with one group.
"""

from __future__ import annotations

import collections
import json

from content_kinds import path_for

# How far outside the observed range a new entry may reach before it is worth a
# sentence. Set from the spread above: within an era the shipped numbers differ
# by up to ×8, so ×3 beyond the ends is roomy enough that a legitimately dearer
# building passes, and still tight enough to catch one an order of magnitude
# out. It is deliberately generous — this check reports, it does not block, and
# a check that cries wolf gets switched off.
TOLERANCE = 3.0

# Below this many samples the "range" is one or two entries and means nothing;
# the check falls back to the whole file, and then keeps quiet.
ENOUGH = 3


# Keys that say what the numbers beside them *mean*. Without these in the path,
# `effects.delta` pools a `resource_delta` of 220 materials with a `stat_delta`
# of 3 morale and then reports the honest one as the outlier — which is how the
# first run of this check produced most of its noise.
DISCRIMINATORS = ("type", "stat", "resource")


def numbers(node, prefix: str, out: dict[str, list[float]]) -> None:
    if isinstance(node, dict):
        mark = ",".join(
            str(node[key]) for key in DISCRIMINATORS
            if isinstance(node.get(key), str)
        )
        here = f"{prefix}[{mark}]" if mark else prefix
        for key, value in node.items():
            numbers(value, f"{here}.{key}" if here else key, out)
    elif isinstance(node, list):
        for item in node:
            numbers(item, prefix, out)
    elif isinstance(node, (int, float)) and not isinstance(node, bool):
        out.setdefault(prefix, []).append(float(node))


def observed(entries, skip_id: str | None = None) -> dict[tuple[str, str], list[float]]:
    """Every number the content uses, keyed by (era, path).

    `skip_id` leaves one entry out — the only honest way to ask whether this
    check would have complained about content that already ships, since an
    entry compared against a range it is itself an end of always passes.
    """
    found: dict[tuple[str, str], list[float]] = collections.defaultdict(list)
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("id") == skip_id:
            continue
        here: dict[str, list[float]] = {}
        numbers(entry, "", here)
        era = entry.get("era") if isinstance(entry.get("era"), str) else "*"
        for path, values in here.items():
            found[(era, path)] += values
            if era != "*":
                found[("*", path)] += values
    return found


def range_for(found, era: str, path: str) -> tuple[float, float] | None:
    """The range this entry's own era uses, and **no wider**.

    An entry that states an era is only comparable to its own era. Falling back
    to the whole file when an era is thin looks harmless and is not: it hands a
    windmill the range a modern power station occupies, and reports the windmill.
    Better to say nothing — the check is worth having only while everything it
    says is worth reading.
    """
    values = found.get((era, path))
    if values and len(values) >= ENOUGH:
        return min(values), max(values)
    return None


def faults_for(entry: dict, found) -> list[str]:
    era = entry.get("era") if isinstance(entry.get("era"), str) else "*"
    here: dict[str, list[float]] = {}
    numbers(entry, "", here)
    out: list[str] = []
    for path, values in sorted(here.items()):
        span = range_for(found, era, path)
        if not span:
            continue
        lo, hi = span
        # A range that includes zero has no meaningful ratio below it, so only
        # the top end is judged there.
        floor = lo / TOLERANCE if lo > 0 else None
        ceiling = hi * TOLERANCE if hi > 0 else None
        for value in values:
            if ceiling is not None and value > ceiling:
                out.append(f"{path}={value:g} — {era} uses {lo:g}…{hi:g}")
            elif floor is not None and 0 < value < floor:
                out.append(f"{path}={value:g} — {era} uses {lo:g}…{hi:g}")
    return out


def check(draft, kind: str) -> list[str]:
    """Every number in the draft that does not belong beside the shipped ones."""
    if not isinstance(draft, list):
        return []
    existing = json.loads(path_for(kind).read_text(encoding="utf-8"))
    found = observed(existing)
    faults: list[str] = []
    for entry in draft:
        if not isinstance(entry, dict):
            continue
        name = entry.get("id", "?")
        faults += [f"{name}: {fault}" for fault in faults_for(entry, found)]
    return faults


def self_check(kind: str) -> list[str]:
    """What this check would say about the content that already ships.

    Leave-one-out, so each entry is judged against the others rather than
    against a range it helped define. Anything this returns is either a real
    outlier in the shipped balance or a false alarm, and both are worth seeing
    before the check is pointed at a two-hundred-entry batch.
    """
    entries = json.loads(path_for(kind).read_text(encoding="utf-8"))
    out: list[str] = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        found = observed(entries, skip_id=entry.get("id"))
        out += [f"{entry.get('id','?')}: {f}" for f in faults_for(entry, found)]
    return out
