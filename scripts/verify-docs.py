#!/usr/bin/env python3
"""Check the documentation against the tree.

Ten mechanical rules, none of which needs Xcode, the network, or the ~18-minute
Core suite:

  1. FMEA      — every `path` · `symbol` cell in docs/FMEA.md resolves to a real
                 file containing that symbol.
  2. LINKS     — every relative Markdown link resolves.
  3. RULES     — docs/RULES.md is numbered contiguously and its header count is
                 the number of rules it actually holds.
  4. ENGINES   — every engine in Core/…/Engine/ is named in
                 docs/CODEMAPS/engines.md (or exempted here, with a reason).
  5. DATA      — every GameData/*.json parses, is listed in
                 docs/CODEMAPS/data.md, and its entry count there is true.
  6. CONTENT   — every LocalizedText in GameData carries `cs` beside `en`
                 (rule 7), checked without building anything.
  7. CLASS     — every document is declared either a living document or a
                 record, because the two are trusted differently.
  8. COUNTS    — a living document may not quote a content or rule count that
                 the tree disagrees with. Records may: their numbers were true
                 on the day they were written.
  9. BASELINE  — a living document may only quote the test counts in the newest
                 row of docs/TEST-BASELINE.md.
 10. HANDOFFS  — every session handoff is listed in docs/handoffs/README.md,
                 and docs/README.md points at the newest one.

Prose is what is left over, and every prose-only claim is a thing nobody checks.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAMEDATA = ROOT / "Core/Sources/EndlessFrontierCore/Resources/GameData"
ENGINE_DIR = ROOT / "Core/Sources/EndlessFrontierCore/Engine"

DOC_ROOTS = ["README.md", "CLAUDE.md", "docs"]

# The living documents: read for the state of the game, so every number in them
# is a claim about today. Everything else in docs/ is a record — a handoff, the
# backlog, a rule's worked example — whose numbers were true when written and
# are not checked. A new document must be added to one list or the other.
LIVING_DOCS = [
    "CLAUDE.md",
    "README.md",
    "docs/README.md",
    "docs/NEXT.md",
    "docs/TEST-BASELINE.md",
    "docs/CODEMAPS/architecture.md",
    "docs/CODEMAPS/engines.md",
    "docs/CODEMAPS/models.md",
    "docs/CODEMAPS/data.md",
    "docs/CODEMAPS/app.md",
    "docs/CODEMAPS/probes.md",
    "docs/CODEMAPS/README.md",
    "docs/architecture/LAYERS.md",
]

# Records, by directory or by name. `RULES.md` and `FMEA.md` are the odd pair:
# they are *live* as instructions and *historical* in their numbers, because a
# rule quotes the measurement that produced it ("411 recipes needed treasure").
RECORD_DIRS = ["docs/handoffs"]
RECORD_FILES = [
    "docs/RULES.md", "docs/FMEA.md", "docs/BACKLOG.md", "docs/DESIGN.md",
    "docs/ROADMAP.md", "docs/NEXT_STEPS.md", "docs/NEXT_PHASE.md",
    "docs/CHRONICLE.md", "docs/COUNCIL.md", "docs/ROADS.md", "docs/NEIGHBOURS.md",
    "docs/RIMWORLD_LAYER.md", "docs/MOUNTS_AND_VEHICLES.md", "docs/ARMS_AND_PROJECTILES.md",
    "docs/RENDER_25D.md",
    "docs/ASSET_SPECIFICATION.md", "docs/AI_PROMPT_LIBRARY.md", "docs/AUDIO-LICENCES.md",
    "docs/HANDOFF-GENERATION.md", "docs/ASSET_SPECIFICATION.md",
]

# A count in a living document that is deliberately about the past. Each needs
# the reason, which is harder to write than the fix usually is.
COUNT_EXEMPT = {
    "73 items": "the equipSlot finding (rule 94) — a measurement, quoted with its date",
    "0 of 152 events": "the reachability sweep of 2026-08-17, kept as the measurement it was",
    "0 of 31 techs": "the same sweep",
    "0 of 49 buildings": "the same sweep",
}

# What a count word counts. `rules` comes from RULES.md, the rest from GameData.
COUNT_WORDS = {
    "buildings": "buildings.json", "techs": "techs.json", "events": "events.json",
    "items": "items.json", "recipes": "recipes.json", "meals": "meals.json",
    "laws": "laws.json", "cults": "cults.json", "quests": "quests.json",
    "biomes": "biomes.json", "plagues": "plagues.json", "motion clips": "motions.json",
    "conveyances": "conveyances.json",
}

# Files in Engine/ that are not engines. Adding one means writing down why it is
# not an engine — which is harder than adding the row to engines.md.
ENGINE_EXEMPT = {
    "SeededRNG": "the RNG itself, documented in architecture.md",
    "Objective": "a model that happens to live beside its engine",
    "WorldReport": "a read-only summary type",
    "StoreBreakdown": "a read-only summary type",
    "TribeCamp": "a model owned by DiplomacyEngine",
    "ColonyBonus": "a lookup table read by ResourceLoop",
    "ColonyRoute": "pathing, listed under the land in engines.md",
    "NameForge": "name generation, no state transition",
    "BalanceHarness": "a probe harness, see probes.md",
    "CouncilAppetite": "the council's scoring, documented under StewardEngine",
}

failures: list[str] = []


def fail(rule: str, message: str) -> None:
    failures.append(f"[{rule}] {message}")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf8", errors="ignore")


# ------------------------------------------------------------------ 1. FMEA

def check_fmea() -> None:
    try:
        fmea = read("docs/FMEA.md")
    except FileNotFoundError:
        fail("FMEA", "docs/FMEA.md is missing")
        return

    cells = re.findall(r"`([^`]+)`\s*·\s*`([^`]+)`", fmea)
    if not cells:
        fail("FMEA", "no `path` · `symbol` Where cells found — has the format changed?")
    for rel, symbol in cells:
        path = ROOT / rel
        if not path.exists():
            fail("FMEA", f"Where cell points at {rel}, which does not exist")
            continue
        if symbol not in path.read_text(encoding="utf8", errors="ignore"):
            fail("FMEA", f"{rel} no longer contains `{symbol}`")


# ----------------------------------------------------------------- 2. LINKS

LINK = re.compile(r"\[[^\]]*\]\(([^)#]+?)(?:#[^)]*)?\)")


def markdown_files() -> list[Path]:
    files: list[Path] = []
    for entry in DOC_ROOTS:
        path = ROOT / entry
        if path.is_dir():
            files.extend(sorted(path.rglob("*.md")))
        elif path.exists():
            files.append(path)
    return files


def check_links() -> None:
    for doc in markdown_files():
        for match in LINK.finditer(doc.read_text(encoding="utf8", errors="ignore")):
            target = match.group(1).strip()
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            if not (doc.parent / target).exists():
                fail("LINKS", f"{doc.relative_to(ROOT)} links to {target}, which does not exist")


# ----------------------------------------------------------------- 3. RULES

RULE = re.compile(r"^(\d+)([a-z]?)\.\s+\*\*", re.M)


def check_rules() -> None:
    try:
        rules = read("docs/RULES.md")
    except FileNotFoundError:
        fail("RULES", "docs/RULES.md is missing")
        return

    entries = RULE.findall(rules)
    if not entries:
        fail("RULES", "no numbered rules found — has the format changed?")
        return

    expected = 0
    for number, suffix in entries:
        value = int(number)
        if suffix:                       # 9b follows 9, does not advance the count
            if value != expected:
                fail("RULES", f"rule {value}{suffix} hangs off {expected}, not off its own number")
            continue
        expected += 1
        if value != expected:
            fail("RULES", f"rule numbering jumps: expected {expected}, found {value}")
            expected = value

    claimed = re.search(r"(\d+)\s+rules", rules)
    if not claimed:
        fail("RULES", "the header does not say how many rules there are")
    elif int(claimed.group(1)) != expected:
        fail("RULES", f"the header claims {claimed.group(1)} rules; there are {expected}")


# --------------------------------------------------------------- 4. ENGINES

def check_engines() -> None:
    try:
        doc = read("docs/CODEMAPS/engines.md")
    except FileNotFoundError:
        fail("ENGINES", "docs/CODEMAPS/engines.md is missing")
        return

    for swift in sorted(ENGINE_DIR.glob("*.swift")):
        name = swift.stem
        if name in ENGINE_EXEMPT or f"`{name}`" in doc:
            continue
        fail("ENGINES", f"{name} is an engine engines.md does not name")


# ------------------------------------------------------------------ 5. DATA

COUNT_ROW = re.compile(r"^\|\s*`([\w.-]+\.json)`\s*\|\s*([\d,]+)(\s+\w+)?\s*\|", re.M)


def entry_count(payload) -> int:
    return len(payload)


def check_data() -> None:
    try:
        doc = read("docs/CODEMAPS/data.md")
    except FileNotFoundError:
        fail("DATA", "docs/CODEMAPS/data.md is missing")
        return

    listed = {m.group(1): int(m.group(2).replace(",", "")) for m in COUNT_ROW.finditer(doc)}

    for path in sorted(GAMEDATA.glob("*.json")):
        name = path.name
        try:
            payload = json.loads(path.read_text(encoding="utf8"))
        except json.JSONDecodeError as error:
            fail("DATA", f"{name} is not valid JSON: {error}")
            continue
        if name not in listed:
            fail("DATA", f"{name} is content data.md does not list")
            continue
        actual = entry_count(payload)
        if listed[name] != actual:
            fail("DATA", f"data.md says {name} holds {listed[name]}; it holds {actual}")

    for name in listed:
        if not (GAMEDATA / name).exists():
            fail("DATA", f"data.md lists {name}, which no longer exists")


# --------------------------------------------------------------- 6. CONTENT

def walk_localized(node, path: str, name: str) -> None:
    if isinstance(node, dict):
        if "en" in node and isinstance(node.get("en"), str):
            czech = node.get("cs")
            if not isinstance(czech, str) or not czech.strip():
                fail("CONTENT", f"{name}: {path} reads in English only (rule 7)")
        for key, value in node.items():
            walk_localized(value, f"{path}.{key}" if path else str(key), name)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            walk_localized(value, f"{path}[{index}]", name)


def check_content() -> None:
    for path in sorted(GAMEDATA.glob("*.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf8"))
        except json.JSONDecodeError:
            continue                     # already reported by check_data
        walk_localized(payload, "", path.name)


# ----------------------------------------------------------------- 7. CLASS

def classified(rel: str) -> str | None:
    if rel in LIVING_DOCS:
        return "living"
    if rel in RECORD_FILES or any(rel.startswith(d + "/") for d in RECORD_DIRS):
        return "record"
    return None


def check_class() -> None:
    for doc in markdown_files():
        rel = str(doc.relative_to(ROOT))
        if classified(rel) is None:
            fail("CLASS", f"{rel} is neither a living document nor a record — "
                          "say which in scripts/verify-docs.py")


# ---------------------------------------------------------------- 8. COUNTS

def content_truth() -> dict[str, int]:
    truth: dict[str, int] = {}
    for word, filename in COUNT_WORDS.items():
        path = GAMEDATA / filename
        if not path.exists():
            continue
        try:
            truth[word] = len(json.loads(path.read_text(encoding="utf8")))
        except json.JSONDecodeError:
            continue
    rules = re.findall(r"^\d+\.\s+\*\*", read("docs/RULES.md"), re.M)
    truth["rules"] = len(rules)
    return truth


def check_counts() -> None:
    truth = content_truth()
    if not truth:
        return
    words = "|".join(sorted(truth, key=len, reverse=True))
    pattern = re.compile(r"(\d[\d,]*)\s+(" + words + r")\b")
    for rel in LIVING_DOCS:
        path = ROOT / rel
        if not path.exists():
            continue
        for number, line in enumerate(path.read_text(encoding="utf8").split("\n"), 1):
            for match in pattern.finditer(line):
                said = int(match.group(1).replace(",", ""))
                actual = truth[match.group(2)]
                if said == actual:
                    continue
                if any(key in line for key in COUNT_EXEMPT):
                    continue
                fail("COUNTS", f"{rel}:{number} says `{match.group(0)}`; "
                               f"the tree holds {actual}")


# -------------------------------------------------------------- 9. BASELINE

BASELINE_ROW = re.compile(r"^\|\s*(\d{4}-\d{2}-\d{2})\s*\|[^|]*\|\s*(\d+)\s*\|\s*(\d+)\s*\|"
                          r"[^|]*\|\s*(\d+)\s*\|", re.M)
CLAIM = re.compile(r"(\d[\d,]*)\s+(Core|App)\s+tests")


def check_baseline() -> None:
    try:
        baseline = read("docs/TEST-BASELINE.md")
    except FileNotFoundError:
        fail("BASELINE", "docs/TEST-BASELINE.md is missing")
        return

    rows = BASELINE_ROW.findall(baseline)
    if not rows:
        fail("BASELINE", "no measurement rows found — has the table changed?")
        return
    newest = max(rows, key=lambda row: row[0])
    truth = {"Core": int(newest[1]), "App": int(newest[3])}

    for rel in LIVING_DOCS:
        if rel == "docs/TEST-BASELINE.md":
            continue
        path = ROOT / rel
        if not path.exists():
            continue
        for number, line in enumerate(path.read_text(encoding="utf8").split("\n"), 1):
            for match in CLAIM.finditer(line):
                said = int(match.group(1).replace(",", ""))
                if said != truth[match.group(2)]:
                    fail("BASELINE", f"{rel}:{number} says `{match.group(0)}`; the newest "
                                     f"baseline row ({newest[0]}) says {truth[match.group(2)]}")


# ------------------------------------------------------------- 10. HANDOFFS

HANDOFF = re.compile(r"HANDOFF-(\d{4}-\d{2}-\d{2})(-evening)?\.md$")


def check_handoffs() -> None:
    folder = ROOT / "docs/handoffs"
    if not folder.is_dir():
        fail("HANDOFFS", "docs/handoffs/ is missing")
        return
    try:
        index = (folder / "README.md").read_text(encoding="utf8")
    except FileNotFoundError:
        fail("HANDOFFS", "docs/handoffs/README.md is missing — the log needs its index")
        return

    handoffs = sorted(p for p in folder.glob("*.md") if HANDOFF.search(p.name))
    if not handoffs:
        fail("HANDOFFS", "no handoffs found in docs/handoffs/")
        return
    for path in handoffs:
        if path.name not in index:
            fail("HANDOFFS", f"{path.name} is not listed in docs/handoffs/README.md")

    def stamp(path: Path) -> tuple[str, int]:
        match = HANDOFF.search(path.name)
        return (match.group(1), 1 if match.group(2) else 0)

    newest = max(handoffs, key=stamp)
    pointer = read("docs/README.md")
    if newest.name not in pointer:
        fail("HANDOFFS", f"docs/README.md does not point at the newest handoff, {newest.name}")


def main() -> int:
    check_fmea()
    check_links()
    check_rules()
    check_engines()
    check_data()
    check_content()
    check_class()
    check_counts()
    check_baseline()
    check_handoffs()

    if failures:
        print(f"verify-docs: {len(failures)} problem(s)\n")
        for line in failures:
            print("  " + line)
        print("\nThe documents are part of the change. Fix them in the same commit.")
        return 1

    print("verify-docs: FMEA targets, links, rule numbering, the engine index, the "
          "content tables, the Czech, every document's class, every count, the test "
          "baseline and the handoff log all resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
