#!/usr/bin/env python3
"""Check the documentation against the tree.

Six mechanical rules, none of which needs Xcode, the network, or the ~18-minute
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


def main() -> int:
    check_fmea()
    check_links()
    check_rules()
    check_engines()
    check_data()
    check_content()

    if failures:
        print(f"verify-docs: {len(failures)} problem(s)\n")
        for line in failures:
            print("  " + line)
        print("\nThe documents are part of the change. Fix them in the same commit.")
        return 1

    print("verify-docs: FMEA targets, links, rule numbering, the engine index, "
          "the content tables and the Czech all resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
