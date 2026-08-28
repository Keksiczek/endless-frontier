#!/usr/bin/env python3
"""Revise a bank that already exists, instead of adding to one.

`generate.py` writes *new* entries: it hands the model a sample and a list of
taken ids and asks for things that are not there yet. That is the wrong verb for
half the work. Twenty grounds share eleven texture marks between them — four of
them `stipple` — and nothing about that is missing content. It is content that
was written one entry at a time and never read as a set.

So this asks a different question: **here is the whole bank, at once; what is
wrong with it as a set?** The model sees every entry rather than eight, which is
the only way to notice that four grounds look identical underfoot or that three
buildings all claim the same accent colour.

Three things make that safe to run against files the game loads:

1. **A revision may not change the roster.** Every id that went in comes back,
   nothing new appears, and the check fails loudly rather than merging a bank
   with an entry silently dropped. This is the failure a revision has that a
   draft does not, and it is the one that would cost a save.
2. **It is scoped.** `--fields texture,texture_alpha` sends the whole bank and
   accepts changes to those keys only; everything else is restored from the
   original before the draft is written. A model asked to look at textures will
   improve your prose on the way past, and prose you did not ask it to touch is
   prose nobody reviewed.
3. **It goes through the same three checks** as anything else, and it prints a
   field-by-field diff first. A revision you have not read is not a revision.

Nothing here runs inside the game — see `Tools/README.md`. It writes a draft;
`generate.py merge` is still what puts anything into `GameData`.

    python3 Tools/revise.py ground --fields texture,texture_alpha
    python3 Tools/revise.py structures --note "the five plant buildings"
    python3 Tools/revise.py ground --dry-run
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import llm  # noqa: E402
from content_kinds import KINDS, path_for  # noqa: E402
from generate import DRAFTS, MODEL_HELP, check, load, warnings  # noqa: E402


SYSTEM = """You revise content for Endless Frontier, a colony simulation set in
one valley, played over decades of in-game years. It is drawn as night-leaning
line art: bone hairlines on slate, almost nothing bright, and every colour value
is dark on purpose.

You are given a **complete** content file and asked what is wrong with it as a
set. Hard rules:

· Return the whole array, every entry, in the same order and with the same ids.
  Never add an id, never drop one, never rename one.
· Change only what you were asked to change. Leave every other field byte for
  byte as you found it.
· An entry that is already right comes back unchanged. Most of them should.
· Every player-visible string is bilingual: `en` and `cs` together, always. The
  Czech is written by somebody who speaks Czech, not translated word for word.
· Return JSON and nothing else."""


def as_entries(answer) -> list[dict]:
    """The array the model meant, whatever it wrapped it in."""
    if isinstance(answer, list):
        return [e for e in answer if isinstance(e, dict)]
    if isinstance(answer, dict):
        for value in answer.values():
            if isinstance(value, list):
                return [e for e in value if isinstance(e, dict)]
    return []


def roster_faults(before: list[dict], after: list[dict]) -> list[str]:
    """Whether this is a revision of the bank or a different bank.

    The check that a draft does not need. `generate.py` is adding entries so a
    changed roster is the point; here a missing id is an entry deleted out of a
    file the game loads, and it would merge without a word.
    """
    was = [e.get("id") for e in before]
    now = [e.get("id") for e in after]
    faults: list[str] = []
    lost = [i for i in was if i not in set(now)]
    gained = [i for i in now if i not in set(was)]
    if lost:
        faults.append(f"{len(lost)} entries came back missing: {', '.join(map(str, lost[:8]))}")
    if gained:
        faults.append(f"{len(gained)} entries were invented: {', '.join(map(str, gained[:8]))}")
    duplicated = [i for i in set(now) if now.count(i) > 1]
    if duplicated:
        faults.append(f"{len(duplicated)} ids came back twice: {', '.join(map(str, duplicated[:8]))}")
    return faults


def scoped(before: list[dict], after: list[dict], fields: set[str] | None) -> list[dict]:
    """The revision, with everything outside `fields` put back as it was.

    Without this a run aimed at `texture` returns a bank with forty descriptions
    quietly reworded — every one of them a change nobody asked for and nobody
    will read, in a file two languages have to agree in.
    """
    if not fields:
        return after
    original = {e.get("id"): e for e in before}
    kept: list[dict] = []
    for entry in after:
        base = dict(original.get(entry.get("id"), {}))
        for key in fields:
            if key in entry:
                base[key] = entry[key]
            elif key in base:
                del base[key]
        kept.append(base)
    return kept


def diff(before: list[dict], after: list[dict]) -> list[str]:
    """One line per field that actually moved."""
    original = {e.get("id"): e for e in before}
    lines: list[str] = []
    for entry in after:
        was = original.get(entry.get("id"))
        if was is None:
            continue
        for key in sorted(set(was) | set(entry)):
            old, new = was.get(key), entry.get(key)
            if old == new:
                continue
            lines.append(f"{entry.get('id')}.{key}: {json.dumps(old, ensure_ascii=False)}"
                         f"  →  {json.dumps(new, ensure_ascii=False)}")
    return lines


def prompt_for(kind: str, entries: list[dict], fields: set[str] | None,
               note: str | None) -> str:
    spec = KINDS[kind]
    scope = (
        f"Change **only** these fields: {', '.join(sorted(fields))}. "
        "Every other field must come back exactly as you found it."
        if fields else
        "Change whatever is genuinely wrong. Most entries should come back "
        "unchanged — a revision that rewrites everything has reviewed nothing."
    )
    return f"""WHAT THIS CONTENT IS

{spec['brief']}

WHAT YOU ARE DOING

This file already exists and the game loads it. You are not adding entries —
you are reading all {len(entries)} of them **as a set** and correcting what only
shows up when they are seen together: entries that are indistinguishable from
each other, a value that is an outlier for no reason, a vocabulary used four
times where a fifth word existed, a Czech line that reads as translated English.

{scope}
{f"WHAT PROMPTED THIS: {note}" if note else ""}

THE WHOLE FILE, {len(entries)} ENTRIES:

{json.dumps(entries, ensure_ascii=False, indent=2)}

Return the whole array, same ids, same order. Nothing else."""


def run(kind: str, fields: set[str] | None, note: str | None,
        temperature: float, dry_run: bool) -> int:
    if kind not in KINDS:
        raise SystemExit(f"no such kind: {kind}. Try: {', '.join(sorted(KINDS))}")
    entries = load(path_for(kind))
    prompt = prompt_for(kind, entries, fields, note)

    if dry_run:
        print(prompt)
        return 0

    print(f"{llm.BACKEND}/{llm.MODEL}: revising {len(entries)} {kind} "
          f"({'all fields' if not fields else ', '.join(sorted(fields))})…",
          flush=True)
    revised = scoped(entries, as_entries(llm.ask(SYSTEM, prompt, temperature=temperature)),
                     fields)

    faults = roster_faults(entries, revised)
    if faults:
        print("\nthis is not a revision of that bank:")
        for fault in faults:
            print(f"  · {fault}")
        return 1

    moved = diff(entries, revised)
    if not moved:
        print("\nnothing changed — the model read it as already right.")
        return 0

    print(f"\n{len(moved)} field(s) changed:")
    for line in moved[:80]:
        print(f"  · {line}")
    if len(moved) > 80:
        print(f"  … and {len(moved) - 80} more")

    # The same three checks a draft answers to. A revision is content going into
    # `GameData` and gets no discount for having been there before — with one
    # exception, and it is the difference between the two verbs. `check` refuses
    # an id that is **already in the file**, because a draft is adding entries
    # and a collision is a clash. Here every id collides and that is the point:
    # `roster_faults` above has already required a one-for-one match, which is a
    # stronger statement than "no duplicates" rather than a weaker one.
    collision = f"already in {KINDS[kind]['file']}"
    problems = [p for p in check(kind, revised) if not p.endswith(collision)]
    if problems:
        print(f"\n{len(problems)} thing(s) to fix before this can be merged:")
        for problem in problems[:40]:
            print(f"  · {problem}")
        return 1
    odd = warnings(kind, revised)
    if odd:
        print(f"\n{len(odd)} number(s) sitting oddly beside the rest:")
        for line in odd[:20]:
            print(f"  ? {line}")

    DRAFTS.mkdir(exist_ok=True)
    out = DRAFTS / f"{kind}-revision-{time.strftime('%Y%m%d-%H%M%S')}.json"
    out.write_text(json.dumps(revised, ensure_ascii=False, indent=2) + "\n")
    print(f"\nclean — read the diff above, then:\n  python3 Tools/generate.py merge {out}")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("kind", help=f"one of: {', '.join(sorted(KINDS))}")
    parser.add_argument("--fields", help="comma-separated keys the revision may touch")
    parser.add_argument("--note", help="what prompted this pass")
    parser.add_argument("--model", help=MODEL_HELP)
    parser.add_argument("--temperature", type=float, default=0.55,
                        help="lower than drafting on purpose: a revision is a "
                             "correction, not an invention")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the prompt and send nothing")
    args = parser.parse_args()

    llm.use_model(args.model)
    fields = {f.strip() for f in args.fields.split(",") if f.strip()} if args.fields else None
    raise SystemExit(run(args.kind, fields, args.note, args.temperature, args.dry_run))


if __name__ == "__main__":
    main()
