#!/usr/bin/env python3
"""Draft game content with a model, check it, then merge it.

**Never runs in the game.** See `llm.py`. This writes JSON on a workstation; the
JSON is what ships, and the app never opens a socket.

    Tools/generate.py kinds                      what can be generated, and how much exists
    Tools/generate.py draft events --count 30    write a draft to Tools/drafts/
    Tools/generate.py check Tools/drafts/x.json  validate without touching the game
    Tools/generate.py merge Tools/drafts/x.json  append into GameData, then run the tests

Three steps and not one, because a model drafting straight into `GameData` is a
model editing the game unsupervised. The draft is a file you read.

The checks here are deliberately the *same* ones the Swift tests make, so a
draft that passes `check` does not fail `swift test` half an hour later:

  * every `{"en": …}` has a non-empty `cs` — the exact walk `ContentTests`
    does, because content that ships half-translated is the one content rule
    this repository actually enforces;
  * no id collides with one already in the file, and no two drafts collide;
  * no closed-vocabulary field holds a value the existing content has never
    used — an effect type `EffectApplier` has never heard of loads fine and
    then quietly does nothing, which is the worst failure available.

`merge` runs the content-facing suites afterwards — `ContentTests`,
`CraftingTests`, `ProductionChainTests`, `FoodChainTests`, `ItemTests` — and
**puts the file back** if they fail, so a bad batch cannot leave the repository
broken. Running only `ContentTests` was not enough: it judges the *shape* of an
entry and never asks whether the things it names can be reached.
"""

from __future__ import annotations

import argparse
import os
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import llm
import magnitudes
import references
from content_kinds import (
    ENUM_KEYS, INTEGER_FIELDS, KINDS, NEEDS_SWIFT_FIRST, READABLE_GLOBAL_STATS,
    READABLE_SETTLEMENT_STATS, ROOT, SHAPES, SUPPLEMENTS, SUPPLEMENTS_BY_KIND,
    WRITABLE_GLOBAL_STATS,
    WRITABLE_SETTLEMENT_STATS, effect_shape_problems, path_for,
)

DRAFTS = Path(__file__).resolve().parent / "drafts"

MODEL_HELP = (
    "override the model for this run — gemini-2.5-flash for volume, "
    "gemini-2.5-pro where the shape is harder than the prose"
)

SYSTEM = """You write content for Endless Frontier, a colony simulation set in one
valley, played over decades of in-game years. A colony starts at seven people and
grows into a village; the player knows the colonists by name.

You are given the real content file and must write more entries **in exactly the
same shape**. Hard rules:

1. Answer with a JSON array of new entries and nothing else.
2. Every piece of player-visible text is an object with `en` and `cs`. The Czech
   is not a translation exercise — it must read as though a Czech writer wrote it
   first. No calques, no English word order, no "byl vytvořen" where a Czech
   would say "vznikl".
3. Use only the field names, effect types, stat names and enum values that appear
   in the examples. Never invent a new kind of effect or condition.
4. Ids are lowercase snake_case, unique, and must not repeat an existing one.
5. Numbers must sit sensibly beside the numbers already in the file. Look at what
   a comparable entry costs or gives and stay in that world.
6. Write about specific things happening to specific people in a specific place.
   A named field, a named family, a particular argument beats a general statement
   every time."""


# ─────────────────────────────────────────────────────────── reading the repo

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def ids_in(entries) -> set[str]:
    return {e["id"] for e in entries if isinstance(e, dict) and isinstance(e.get("id"), str)}


def vocabulary(entries, kind: str | None = None) -> dict[str, set[str]]:
    """Every value the existing content uses for a closed-vocabulary key.

    Collected rather than declared: the schema files cover two of the eleven data
    kinds, and a hand-kept list of effect types would be wrong within a month.
    """
    found: dict[str, set[str]] = {}
    keys = closed_keys(entries)

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key in keys and isinstance(value, str):
                    found.setdefault(key, set()).add(value)
                elif key in keys and isinstance(value, list):
                    for item in value:
                        if isinstance(item, str):
                            found.setdefault(key, set()).add(item)
                else:
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(entries)
    for key, extra in SUPPLEMENTS.items():
        if key in found:
            found[key] |= extra
    # …and where this kind has its own vocabulary for a key, that one wins
    # outright. See `SUPPLEMENTS_BY_KIND`.
    for key, own in (SUPPLEMENTS_BY_KIND.get(kind or "", {})).items():
        found[key] = set(own)
    return found


def closed_keys(entries) -> set[str]:
    """Keys whose values are a closed set, whether anyone listed them or not.

    `ENUM_KEYS` is hand-kept and was wrong three times in one day — `equipSlot`,
    then `class`, each one a field the game validates strictly and the checker
    had never heard of. A hand-kept list of closed vocabularies is the same
    mistake as a hand-kept schema.

    So the list is now a floor rather than the whole answer: anything the
    content uses few values of, many times over, is treated as closed too. The
    two halves cover different ground — the hand list holds the keys with
    *many* legal values (`type`, `look`), the measurement finds the keys nobody
    thought of.

    Reference keys are left out on purpose: `references.py` judges those by
    whether the thing exists, and a draft that introduces a building and a
    recipe for it in one batch is a good draft, not an invented word.
    """
    counts: dict[str, dict[str, int]] = {}

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if isinstance(value, str):
                    counts.setdefault(key, {})[value] = counts.setdefault(key, {}).get(value, 0) + 1
                elif isinstance(value, list):
                    for item in value:
                        if isinstance(item, str):
                            counts.setdefault(key, {})[item] = counts.setdefault(key, {}).get(item, 0) + 1
                        else:
                            walk(item)
                else:
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(entries)
    measured = {
        key for key, seen in counts.items()
        if len(seen) <= 12 and sum(seen.values()) >= 3 * len(seen)
    }
    return (set(ENUM_KEYS) | measured) - set(references.REFERENCES)


def sample(entries, count: int) -> list:
    """Examples spread across the file rather than taken off the top, so the
    model sees the range of what an entry can be and not just the first kind."""
    if len(entries) <= count:
        return list(entries)
    step = len(entries) / count
    return [entries[int(i * step)] for i in range(count)]


# ────────────────────────────────────────────────────────────────── checking

def untranslated(node, path: str, out: list[str]) -> None:
    """The walk `ContentTests.allContentIsBilingual` makes, in Python."""
    if isinstance(node, dict):
        en = node.get("en")
        if isinstance(en, str) and en:
            cs = node.get("cs")
            if not isinstance(cs, str) or not cs.strip():
                out.append(path)
            elif cs.strip() == en.strip():
                out.append(f"{path} (Czech identical to English)")
            return
        name = f"{path}/{node['id']}" if isinstance(node.get("id"), str) else path
        for key, value in node.items():
            untranslated(value, f"{name}.{key}", out)
    elif isinstance(node, list):
        for item in node:
            untranslated(item, path, out)


def bad_stat(node: dict) -> str | None:
    """Whether this object's `stat` names something the game can act on.

    Judged the way the Swift judges it, which is not one rule but two: an effect
    *writes* through `applying(delta:to:)`, whose `default: break` swallows an
    unknown name whole, while a condition *reads* through `WorldQuery`, which
    falls through to `ResourceType`. So `global.knowledge` is a perfectly good
    thing to test and a dead thing to set, and a checker with one list for both
    either misses the first case or cries wolf on the second.
    """
    raw = node.get("stat")
    if not isinstance(raw, str):
        return None
    writing = node.get("type") == "stat_delta"
    scope, dot, name = raw.partition(".")
    settlement = scope.startswith("settlement:")
    if not dot:
        # `StatPath.parse` leaves a bare name with an empty stat, so it can only
        # ever be read (era milestones), never written.
        if writing:
            return f"{raw} (no scope — a bare name sets nothing)"
        name, settlement = scope, False
    if settlement:
        allowed = WRITABLE_SETTLEMENT_STATS if writing else READABLE_SETTLEMENT_STATS
    else:
        allowed = WRITABLE_GLOBAL_STATS if writing else READABLE_GLOBAL_STATS
    if name in allowed:
        return None
    return f"{raw} ({'sets' if writing else 'reads'} nothing)"


def strange_values(node, allowed: dict[str, set[str]], out: list[str]) -> None:
    if isinstance(node, dict):
        fault = bad_stat(node)
        if fault:
            out.append(f"stat {fault}")
        for key, value in node.items():
            values = [value] if isinstance(value, str) else (
                [v for v in value if isinstance(v, str)] if isinstance(value, list) else []
            )
            # `allowed` is the whole answer: it already holds the hand-listed
            # keys *and* the ones measured out of the content. Asking
            # `ENUM_KEYS` again here re-imposed the hand list and threw the
            # measured half away — which is how `class: armor_bonus` passed a
            # check that had the right vocabulary sitting in front of it.
            if key in allowed:
                for item in values:
                    if item not in allowed[key]:
                        out.append(f"{key}={item}")
            if not isinstance(value, str):
                strange_values(value, allowed, out)
    elif isinstance(node, list):
        for item in node:
            strange_values(item, allowed, out)


def load_drafted_items() -> list:
    """Items sitting in `Tools/drafts` that are not merged yet.

    A batch usually drafts items and the recipes that use them together, so a
    recipe naming an item from its own batch is a good draft, not a fault —
    the same reasoning `references.py` already applies to ids.
    """
    out: list = []
    drafts = ROOT / "Tools" / "drafts"
    if not drafts.is_dir():
        return out
    for path in sorted(drafts.glob("items-*.json")):
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(loaded, list):
            out += [e for e in loaded if isinstance(e, dict)]
    return out


def is_revision(path: Path) -> bool:
    """Whether this draft **replaces** the bank rather than adding to it.

    `revise.py` writes the whole file back with the same ids, so every one of
    them collides with the file and the collision check — which is right for a
    draft — refuses the merge outright. Marked in the name because the merge is
    the one place both verbs meet, and a flag would let a revision be merged as
    a draft by mistake: appending twenty grounds that are already there.
    """
    return "-revision-" in path.name


def check(kind: str, draft: list, revision: bool = False) -> list[str]:
    """Everything wrong with a draft, in one list. Empty means it may be merged."""
    existing = load(path_for(kind))
    allowed = vocabulary(existing, kind)
    faults: list[str] = []

    if not isinstance(draft, list):
        return ["the draft is not a JSON array"]

    known = ids_in(existing)
    seen: set[str] = set()
    for i, entry in enumerate(draft):
        if not isinstance(entry, dict):
            faults.append(f"[{i}] is not an object")
            continue
        entry_id = entry.get("id")
        if not isinstance(entry_id, str) or not re.fullmatch(r"[a-z0-9_]+", entry_id):
            faults.append(f"[{i}] id {entry_id!r} is not lowercase snake_case")
            continue
        if entry_id in known and not revision:
            faults.append(f"{entry_id}: already in {KINDS[kind]['file']}")
        if entry_id in seen:
            faults.append(f"{entry_id}: appears twice in the draft")
        seen.add(entry_id)

        # Every key the existing entries agree on has to be there too…
        required = set.intersection(*(set(e) for e in existing)) if existing else set()
        for key in sorted(required - set(entry)):
            faults.append(f"{entry_id}: missing {key}")
        # …and nothing may be there that no existing entry has. A field the
        # loader has never heard of is dropped in silence, so the entry loads
        # looking complete and quietly does less than it says.
        # `new_fields` is the escape hatch for the one case this check gets
        # wrong: a field the *Swift* has just learned and no row uses yet. The
        # check compares against the file because it cannot read the decoder, so
        # the first entry to use a new field always looks like a typo. Declaring
        # it in `content_kinds.py` is one deliberate line; leaving the check out
        # would cost the fault it exists to catch.
        known_keys = set().union(*(set(e) for e in existing)) if existing else set()
        known_keys |= set(KINDS[kind].get("new_fields", ()))
        for key in sorted(set(entry) - known_keys):
            faults.append(f"{entry_id}: field {key!r} exists nowhere in {KINDS[kind]['file']}")

    # **A recipe is made of stuff, not of finished things.**
    #
    # `references.py` checks that every material a recipe names *exists*, and it
    # passed a hundred drafted recipes whose ingredients were a hardwood cudgel,
    # a woollen cloak and a brass blunderbuss — all real items, none of them a
    # material. `CraftingTests` refuses them, so the merge gate caught it after
    # a nine-minute test run; the checker had nothing to say. The same shape as
    # the vocabulary gap one gate up: the name pointed at something real and the
    # *kind* of thing was never asked about.
    if kind == "recipes":
        items = {e["id"]: e for e in load(path_for("items"))}
        drafted_items = {e.get("id"): e for e in load_drafted_items()}
        for entry in draft:
            if not isinstance(entry, dict):
                continue
            for material in sorted((entry.get("materials") or {})):
                found = items.get(material) or drafted_items.get(material)
                if found is None:
                    continue          # `references.py` says this one properly
                if found.get("slot") != "material":
                    faults.append(
                        f"{entry.get('id')}: {material} is a "
                        f"{found.get('slot')}, not a material — a bench takes "
                        f"stuff apart, it does not eat finished gear")

    english: list[str] = []
    untranslated(draft, kind, english)
    faults += [f"reads in English to a Czech player: {p}" for p in english]

    # The same escape hatch as `new_fields`, one level down: a *value* the Swift
    # has just learned and no row uses yet. `riding` was a real activity with a
    # case in the enum, a clip selector arm and a test, and the vocabulary is
    # measured out of the file — so the first clip to use it looked like a typo.
    for key, values in KINDS[kind].get("new_values", {}).items():
        allowed.setdefault(key, set()).update(values)

    odd: list[str] = []
    strange_values(draft, allowed, odd)
    faults += [f"value the game has never used: {v}" for v in sorted(set(odd))]

    # Last, because it is the only check that has to read the whole repository:
    # an entry can be flawless on its own and still name a tech, a building or a
    # world flag that does not exist, and that entry loads and then waits for
    # ever.
    faults += [f"points at nothing: {r}" for r in references.check(draft, kind)]

    # And an effect can name a legal type and still be the wrong *shape*. The
    # vocabulary check knows the words `EventEffect` accepts; this knows what
    # each of them reads. Three drafts in a row passed everything above and then
    # failed to decode — `unlock_tech` with no `techId`, a `region_hazard`
    # written as a `region_kind`, a `remove_pawn` carrying a `count` that
    # nothing reads and that therefore removed one person instead of two.
    if kind == "events":
        for entry in draft:
            if not isinstance(entry, dict):
                continue
            for problem in effect_shape_problems(entry):
                faults.append(f"{entry.get('id', '?')}: {problem}")

    # A worn thing with nothing said about how it looks is content that loads
    # and is then drawn as a guess — the same fault as a motion clip nothing
    # selects, one layer up. The Swift falls back to rarity so a bare entry is
    # not a crash, and that is exactly why it has to be caught here: it would
    # never announce itself.
    if kind == "items":
        for entry in draft:
            if not isinstance(entry, dict) or entry.get("equipSlot") != "armor":
                continue
            worn = entry.get("armour")
            name = entry.get("id", "?")
            if not isinstance(worn, dict):
                faults.append(f"{name}: worn, and no `armour` block to draw it from")
                continue
            if "material" not in worn:
                faults.append(f"{name}: `armour` with no material")
            if worn.get("coverage") == "head" and not worn.get("helm"):
                faults.append(f"{name}: covers the head and draws nothing on it")
            tint = worn.get("tint")
            if tint is not None and not (isinstance(tint, (int, float)) and 0 <= tint <= 1):
                faults.append(f"{name}: tint {tint!r} is not a hue in 0…1")

    faults += malformed(draft)
    return faults


def malformed(node, out: list[str] | None = None) -> list[str]:
    """Typed records missing a field the Swift decoder demands.

    A value check cannot see this: `colony_production` is a real effect type and
    `amount` is a real word, but that pair throws `keyNotFound("perTick")` and
    takes the file with it.
    """
    out = [] if out is None else out
    if isinstance(node, dict):
        shape = SHAPES.get(node.get("type")) if isinstance(node.get("type"), str) else None
        if shape:
            for field in shape["needs"]:
                if field not in node:
                    out.append(f"{node['type']} needs '{field}' — "
                               f"got {sorted(k for k in node if k != 'type')}")
            for field in shape["needs"]:
                if (node["type"], field) in INTEGER_FIELDS and field in node:
                    value = node[field]
                    if not isinstance(value, int) or isinstance(value, bool):
                        out.append(f"{node['type']}.{field}={value!r} must be a whole number")
        for value in node.values():
            malformed(value, out)
    elif isinstance(node, list):
        for item in node:
            malformed(item, out)
    return out


def warnings(kind: str, draft: list) -> list[str]:
    """Things worth a look that are not grounds for refusing the draft.

    Balance is a judgement, not a rule. A number outside the range its era uses
    is usually a model that lost its sense of scale, and occasionally the one
    genuinely expensive building the era was missing — so this prints and does
    not block. Every other check here blocks, and that difference is the point.
    """
    return magnitudes.check(draft, kind)


# ───────────────────────────────────────────────────────────────── the steps

def do_kinds() -> None:
    print("generate into these:\n")
    for kind, spec in KINDS.items():
        entries = load(path_for(kind))
        print(f"  {kind:<11} {len(entries):>4} entries   {spec['file']}")
    print("\nasked for, but Swift work first:\n")
    for kind, why in NEEDS_SWIFT_FIRST.items():
        print(f"  {kind:<11} {why}")


def as_list(answer) -> list:
    """A model that wrapped the array in an object; take the array back out."""
    if isinstance(answer, list):
        return answer
    if isinstance(answer, dict):
        for value in answer.values():
            if isinstance(value, list):
                return value
    return []


def prompt_for(kind: str, count: int, examples: int, note: str | None,
               taken: set[str]) -> str:
    entries = load(path_for(kind))
    spec = KINDS[kind]
    allowed = vocabulary(entries, kind)
    shown = sample(entries, examples)
    vocab_lines = "\n".join(
        f"  {key}: {', '.join(sorted(values))}"
        for key, values in sorted(allowed.items()) if len(values) <= 60
    )
    # World flags are the same trap as `crafting` (rule 41) and worse, because
    # the pattern *looks* open: a model shown `cleared:dungeon` concludes it may
    # invent `cleared:dragons_tooth_pass`, and writes a quest that waits for
    # ever. There are only about twenty flags the running game can ever set, so
    # the honest thing is to hand over all of them.
    # The same lesson as the flags and as `crafting`, for the third time: a model
    # shown a field called `outputItemID` and no list of item ids writes a
    # plausible one. `iron_tiller`, `leather_saddle`, `construction_yard` — all
    # perfectly sensible names for things this game does not have, and fifty-five
    # recipes that could never make anything. Hand over the real ids.
    reference_lines = ""
    used = {
        key: target for key, target in references.REFERENCES.items()
        if f'"{key}"' in json.dumps(shown)
    }
    if used:
        blocks = []
        for target in sorted(set(used.values())):
            ids = sorted(references.ids_of(target))
            keys = sorted(k for k, t in used.items() if t == target)
            blocks.append(
                f"  {', '.join(keys)} must name one of these {len(ids)} "
                f"{target}:\n    " + ", ".join(ids)
            )
        reference_lines = (
            "\n\nIDS THAT EXIST. Every one of these fields must name something "
            "from its list — an id you invent is an entry that loads and can "
            "never do anything:\n\n" + "\n\n".join(blocks)
        )

    flag_lines = ""
    if json.dumps(shown).find("worldFlag") >= 0:
        flags = sorted(references.settable_flags())
        flag_lines = (
            "\n\nTHE ONLY WORLD FLAGS THAT EXIST. Nothing else can ever become "
            "true, so a condition on anything else waits for ever — do not "
            "invent place names:\n\n  " + ", ".join(flags)
        )
    return f"""WHAT THIS CONTENT IS

{spec['brief']}

WHAT WOULD HELP MOST RIGHT NOW: {spec['wants']}
{f"ALSO: {note}" if note else ""}

THE ONLY VALUES YOU MAY USE for these fields:

{vocab_lines}{reference_lines}{flag_lines}

THESE IDS ARE TAKEN — every one of yours must be different:

{', '.join(sorted(taken))}

HERE ARE {len(shown)} EXISTING ENTRIES IN FULL — match this shape exactly:

{json.dumps(shown, ensure_ascii=False, indent=2)}

Now write {count} new entries as a JSON array. Nothing else."""


def do_draft(kind: str, count: int, examples: int, note: str | None,
             per_call: int = 8, temperature: float = 0.95) -> Path:
    """Ask in batches until there are `count` usable entries.

    One request for forty entries is two failures waiting: the answer runs into
    `maxOutputTokens` and comes back truncated, and a model writing forty ids in
    one breath starts repeating itself near the end. Small batches, with every
    id handed out so far fed back in as forbidden, keep both away — and a run
    that dies halfway still leaves everything it had collected.
    """
    existing = ids_in(load(path_for(kind)))
    taken = set(existing)
    collected: list[dict] = []
    barren = 0

    DRAFTS.mkdir(exist_ok=True)
    out = DRAFTS / f"{kind}-{time.strftime('%Y%m%d-%H%M%S')}.json"

    while len(collected) < count and barren < 3:
        want = min(per_call, count - len(collected))
        # Flushed, because a run of any length is watched through a pipe (`| tee`,
        # `| tail`), and Python block-buffers stdout the moment it is not a
        # terminal — which turns an hour's progress into an hour of silence
        # followed by all of it at once.
        print(f"  {llm.BACKEND}/{llm.MODEL}: {len(collected)}/{count} {kind}, "
              f"asking for {want}…", flush=True)
        try:
            batch = as_list(llm.ask(SYSTEM, prompt_for(kind, want, examples, note, taken),
                                    temperature=temperature))
        except Exception as error:  # noqa: BLE001 — a dead batch must not lose the rest
            print(f"    batch failed: {error}")
            barren += 1
            continue

        fresh = [
            entry for entry in batch
            if isinstance(entry, dict)
            and isinstance(entry.get("id"), str)
            and entry["id"] not in taken
        ]
        if not fresh:
            barren += 1
            print("    nothing new in that batch")
            continue
        barren = 0
        for entry in fresh:
            taken.add(entry["id"])
        collected += fresh
        # Written after every batch, so an interrupted run keeps its work.
        out.write_text(json.dumps(collected, ensure_ascii=False, indent=2) + "\n",
                       encoding="utf-8")

    print(f"\nwrote {len(collected)} to {out}")
    report(kind, collected)
    return out


def do_batch(jobs: list[str], per_call: int, examples: int, note: str | None) -> None:
    """`events:60 items:40 quests:20` — a night's work in one command.

    Sequential on purpose. Parallel batches cannot see each other's ids, and
    the whole reason drafting is batched is that a model repeats itself the
    moment it stops being told what is already taken.
    """
    plan: list[tuple[str, int]] = []
    for job in jobs:
        kind, _, count = job.partition(":")
        if kind not in KINDS:
            raise SystemExit(f"{kind!r} is not a kind — try: {', '.join(sorted(KINDS))}")
        plan.append((kind, int(count) if count else 20))

    written: list[tuple[str, Path]] = []
    for kind, count in plan:
        print(f"\n── {kind} ×{count} " + "─" * 40)
        try:
            written.append((kind, do_draft(kind, count, examples, note, per_call=per_call)))
        except KeyboardInterrupt:
            print("\nstopped — what was drafted is on disk")
            break
        except Exception as error:  # noqa: BLE001
            # A night's run is five kinds deep; the third one dying must not
            # take the two behind it. Every kind writes its own file after
            # every batch, so the loss is bounded at this kind's last batch.
            print(f"\n{kind} failed: {error}\n  — carrying on with the rest")

    print("\n" + "═" * 60)
    if not written:
        raise SystemExit("nothing drafted")
    print("drafts written — read them, then merge the ones you want:\n")
    for kind, path in written:
        print(f"  python3 Tools/generate.py merge {path.relative_to(ROOT)}")


def report(kind: str, draft, revision: bool = False) -> bool:
    # Nothing is not clean. Every check below passes trivially on an empty
    # array, so a run that failed every call still printed "ready to merge" and
    # handed over a merge command — the same silent-success shape as a decoder
    # that swallows its error, this time in the tool built to catch those.
    if isinstance(draft, list) and not draft:
        print("\nempty — the run produced nothing. Read the errors above; "
              "there is nothing here to merge.")
        return False
    faults = check(kind, draft, revision=revision)
    if faults:
        print(f"\n{len(faults)} thing(s) to fix before this can be merged:")
        for fault in faults[:40]:
            print(f"  · {fault}")
        if len(faults) > 40:
            print(f"  … and {len(faults) - 40} more")
        return False

    odd = warnings(kind, draft)
    if odd:
        print(f"\n{len(odd)} number(s) sitting oddly beside the existing ones — "
              "read these, then merge if they are what you meant:")
        for line in odd[:20]:
            print(f"  ? {line}")
        if len(odd) > 20:
            print(f"  … and {len(odd) - 20} more")
    print("\nclean — ready to merge")
    return True


def kind_of(draft_path: Path) -> str:
    stem = draft_path.name.split("-")[0]
    if stem not in KINDS:
        raise SystemExit(f"cannot tell what {draft_path.name} is; name it <kind>-….json")
    return stem


def still_being_written(path: Path, settle: float = 2.0) -> bool:
    """Whether something is still appending to this draft.

    `draft` rewrites its file after every batch, so a run that is still going
    has a file that keeps changing under you. Merging one mid-run reads however
    many entries happened to be there at that instant and silently leaves the
    rest behind — which is exactly what happened the first time this was used
    in anger: a draft at 30 was merged, the run carried on to 40, and the last
    ten looked like they had vanished.
    """
    before = path.stat().st_mtime_ns, path.stat().st_size
    time.sleep(settle)
    return (path.stat().st_mtime_ns, path.stat().st_size) != before


def do_merge(draft_path: Path) -> None:
    kind = kind_of(draft_path)
    if still_being_written(draft_path):
        raise SystemExit(
            f"{draft_path.name} is still being written — the run that is "
            "drafting it has not finished. Wait for it, then merge."
        )
    draft = load(draft_path)
    revision = is_revision(draft_path)
    if not report(kind, draft, revision=revision):
        raise SystemExit("not merged")

    target = path_for(kind)
    if revision:
        was = ids_in(load(target))
        now = ids_in(draft)
        if was != now:
            raise SystemExit(
                f"not merged: a revision must carry every id and no others — "
                f"{len(was - now)} missing, {len(now - was)} invented"
            )
    backup = target.with_suffix(".json.before-merge")
    # A run killed between the copy and the outcome leaves its backup behind,
    # and `GameData` is a **bundled resource directory** — so the stray file is
    # copied into the app, shows up in `git status` as something to commit, and
    # sits there looking like content. Two of them had been in the tree for
    # days. Sweep before writing a new one.
    for stale in target.parent.glob("*.json.before-merge"):
        stale.unlink()
    shutil.copy(target, backup)
    # A revision **replaces**; a draft appends. Merging a revision as a draft
    # would put twenty grounds into a file that already has them.
    merged = draft if revision else load(target) + draft
    target.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{'revised' if revision else 'merged'} {len(draft)} in {target.name} "
          f"({len(merged)} total) — running the tests")

    result = subprocess.run(
        # **Not just `ContentTests`.** That suite checks the shape of the
        # content — bilingual text, ids, era gates — and says nothing about
        # whether a recipe's ingredients exist or a meal can ever be cooked.
        # Sixty recipes merged "tests green" and then failed three other suites:
        # six asked for `flint`, which is not an item, and for a stone mortar,
        # which is a tool rather than something you use up. A gate that runs a
        # narrower suite than the content can break is a gate that says yes to
        # the breakage.
        ["swift", "test", "--filter",
         "ContentTests|CraftingTests|ProductionChainTests|FoodChainTests|ItemTests"]
        # SwiftPM takes a lock on the build directory, so a merge run while
        # anything else is testing the same package simply waits — for the
        # length of the other run, which for the full suite is over an hour.
        # `EF_SCRATCH` gives this gate a build directory of its own.
        + (["--scratch-path", os.environ["EF_SCRATCH"]]
           if os.environ.get("EF_SCRATCH") else []),
        cwd=ROOT / "Core", capture_output=True, text=True,
    )
    if result.returncode != 0:
        shutil.move(backup, target)
        # **Both streams.** A failing *test* writes to stdout and a failing
        # *build* writes to stderr, and printing only the first turned "the
        # test target does not compile" and "another SwiftPM already holds the
        # lock" into `tests failed:` followed by nothing at all — a silent
        # failure in the tool whose whole job is catching silent failures.
        tail = "\n".join(
            (result.stdout.strip() + "\n" + result.stderr.strip()).strip().splitlines()[-25:]
        )
        raise SystemExit(f"merge gate failed, {target.name} put back:\n{tail}")
    backup.unlink()
    print("tests green — merged")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("kinds")

    draft = sub.add_parser("draft")
    draft.add_argument("kind", choices=sorted(KINDS))
    draft.add_argument("--count", type=int, default=20)
    draft.add_argument("--per-call", type=int, default=8,
                       help="entries per request; small batches beat one long one")
    draft.add_argument("--examples", type=int, default=6,
                       help="how many existing entries to show the model")
    draft.add_argument("--temperature", type=float, default=0.95)
    draft.add_argument("--note", help="anything extra to ask for this run")
    draft.add_argument("--model", help=MODEL_HELP)

    batch = sub.add_parser("batch")
    batch.add_argument("jobs", nargs="+", metavar="KIND:COUNT")
    batch.add_argument("--per-call", type=int, default=8)
    batch.add_argument("--examples", type=int, default=6)
    batch.add_argument("--note")
    batch.add_argument("--model", help=MODEL_HELP)

    checker = sub.add_parser("check")
    checker.add_argument("draft", type=Path)

    merger = sub.add_parser("merge")
    merger.add_argument("draft", type=Path)

    args = parser.parse_args()
    llm.use_model(getattr(args, "model", None))
    if args.command == "kinds":
        do_kinds()
    elif args.command == "draft":
        do_draft(args.kind, args.count, args.examples, args.note,
                 per_call=args.per_call, temperature=args.temperature)
    elif args.command == "batch":
        do_batch(args.jobs, args.per_call, args.examples, args.note)
    elif args.command == "check":
        sys.exit(0 if report(kind_of(args.draft), load(args.draft)) else 1)
    elif args.command == "merge":
        do_merge(args.draft)


if __name__ == "__main__":
    main()
