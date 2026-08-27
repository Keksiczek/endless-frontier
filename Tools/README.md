# Tools

Small one-shot scripts that produce something checked into the repo. Nothing
here is part of the game: these run on a workstation, and only what they write
ships.

## MakeAppIcon.swift

Draws `App/Assets.xcassets/AppIcon.appiconset/appicon-1024.png` — the icon in
the game's own direction: deep slate night, bone hairlines, one amber lantern,
a settlement seen from the dark. The same gabled silhouette
`SettlementStructures` draws on the canvas, so the icon is the game rather than
a picture of a house.

```bash
swift Tools/MakeAppIcon.swift App/Assets.xcassets/AppIcon.appiconset/appicon-1024.png
```

`appicon-1024-previous.png` is the icon this replaced (a house under a rocket),
kept so the change is one `cp` to undo.

---

# Content generation

**Nothing here runs inside the game.** Endless Frontier is offline-first: there
is no URLSession in the simulation path and no API key ships in the app. These
scripts run on a workstation, write JSON into `GameData`, and the JSON is what
the player gets. If any of this is ever called at play time, that rule has been
broken.

## Setting up

**No API key.** The default backend is Vertex, which signs each call with a
short-lived token from `gcloud auth print-access-token` and bills the Cloud
project — so there is no long-lived secret anywhere in the repository, and
nothing to leak or rotate. A gitignored `.env` at the repository root says which
project pays:

```
EF_BACKEND=vertex
GOOGLE_CLOUD_PROJECT=…
```

`gcloud auth login` once and that is the whole setup. `EF_BACKEND=gemini` or
`anthropic` are there for a workstation without gcloud, and those two do want a
key (`GEMINI_API_KEY` / `GOOGLE_API_KEY`, `ANTHROPIC_API_KEY`) in the same file.

### Which model

`EF_MODEL` sets the default; `--model` overrides it for one run.

| | |
|---|---|
| `gemini-2.5-flash` | The volume. Items, meals, recipes, the flavour half of the events — anything where there is a clear existing pattern to match and the work is *more of it*. Cheap enough that a thousand entries is not a decision. |
| `gemini-2.5-pro` | Where the shape is harder than the prose: a law that has to cost somebody something, an event whose choice is a real dilemma, a tech that has to sit correctly in the DAG. Flash writes these fluently and gets the *balance* wrong. |

```bash
python3 Tools/generate.py batch items:120 meals:40 --model gemini-2.5-flash
python3 Tools/generate.py batch laws:15 --model gemini-2.5-pro
```

## Revising a bank that already exists

`generate.py` adds entries. `revise.py` reads a whole bank at once and corrects
it **as a set** — which is the only way to notice that four of twenty grounds
share `stipple`, or that three buildings claim the same accent colour. One entry
at a time cannot see that, and neither can a sample of eight.

```bash
python3 Tools/revise.py ground --fields texture,texture_alpha
python3 Tools/revise.py structures --note "the five plant buildings read alike"
python3 Tools/revise.py ground --dry-run          # print the prompt, send nothing
```

Three things make it safe to point at a file the game loads:

- **The roster may not change.** Every id in, every id out, none invented and
  none dropped — a revision that loses an entry would merge in silence, and it
  is the one failure a draft cannot have.
- **`--fields` is a fence, not a hint.** Everything outside it is restored from
  the original before the draft is written, so a run aimed at textures cannot
  quietly reword forty descriptions in two languages.
- **It prints a field-by-field diff** and answers to the same three checks.
  A revision you have not read is not a revision.

It writes a draft; `generate.py merge` is still the only thing that touches
`GameData`. Temperature defaults to 0.55 rather than 0.95: a revision is a
correction, not an invention.

## Using it

```bash
python3 Tools/generate.py kinds
python3 Tools/generate.py draft events --count 30
python3 Tools/generate.py check Tools/drafts/events-20260817-204500.json
python3 Tools/generate.py merge Tools/drafts/events-20260817-204500.json
```

Three steps and not one, on purpose: a model drafting straight into `GameData`
is a model editing the game unsupervised. **The draft is a file you read.**
Nothing reaches the game until you say so.

`--note` passes anything extra for one run:

```bash
python3 Tools/generate.py draft events --count 40 --note "winter events; a colony of forty or more"
```

## What the check is for

`check` makes the same judgements the Swift tests make, so a draft that passes
here does not fail `swift test` half an hour later:

- every `{"en": …}` has a real `cs` — and a `cs` identical to the English counts
  as missing, which is how a lazy translation usually arrives;
- no id collides with an existing one, or with another entry in the same draft;
- every entry has the keys all the existing entries agree on;
- no closed-vocabulary field holds a value the game has never used. This is the
  important one: an effect type `EffectApplier` has never heard of loads without
  complaint and then silently does nothing;
- every stat an effect *writes* is one the game can write. Reading and writing
  take different sets — `GlobalStats.applying` ends in `default: break`, so
  `global.knowledge` is a fine thing to test and a dead thing to set — and the
  checker keeps the two lists apart rather than crying wolf on the good half;
- **every name points at something.** `references.py`: a tech that does not
  exist, a building that does not exist, a world flag nothing in the game ever
  sets. This one only fires against the whole repository, and it earned its
  place immediately — the first quests a model wrote were flawless JSON waiting
  for the techs `trade` and `alchemy`, neither of which is real, and for a flag
  no engine sets. They would have loaded, and then waited for ever.

Those all **block**. One more only reports:

- **numbers that do not sit beside the existing ones** (`magnitudes.py`). A
  workshop costing 500 materials in the first era is spelled correctly, points
  at real things, reads well in both languages, and ruins the game. No
  threshold is written down — the range is measured out of the shipped content,
  per era, because era is the whole difference: `cost.materials` spans ×125
  across the game and only ×1–×8 inside one era.

  It prints rather than refuses, because balance is a judgement: the number
  outside the range is usually a model that lost its sense of scale and
  occasionally the one expensive building that era was missing. Tested
  leave-one-out against everything that ships — each entry judged by the others
  rather than by a range it helped define — it has two things to say about 299
  entries, and both are entries that really are the extreme of their group.

`merge` appends, runs `swift test --filter ContentTests`, and **puts the file
back** if they fail — a bad batch cannot leave the repository broken.

## When a long run dies

It does not lose the work. `draft` writes its file after **every batch**, so an
interrupted run keeps everything it had collected; `batch` catches a failing
kind and carries on with the ones behind it. The blast radius of a crash is one
kind's last batch of eight.

## What it can and cannot write

`kinds` prints both lists. Eleven data files can be generated into today.
Four things that were asked for cannot, because they are code and not data:
animals, pawn traits, flora and colonist names. Each needs a data file and a
loader in Swift first; generating into a file nothing reads would just look
like progress.

The line worth keeping straight is **content against mechanics**. Generation
makes the world wider inside the rules that exist; it cannot make a new rule.
Horses are the clean example. A model can write, today, the saddle and the
harness and the cart (`items`), the stable that houses them (`buildings`), the
husbandry that unlocks it (`techs`), and a dozen events about a mare foaling in
a bad winter. What it cannot write is a colonist *riding* — that a mount halves
a haul's walk is `HaulEngine` and `AgentMotion`, and no amount of JSON puts it
there. Write the mechanic first, then generate a hundred things that use it;
the other order produces a stable nobody can stable anything in.

Biomes are the counter-example, and the reason widening the map is cheap: six
exist, `MapGenerator` reads them from the file, and a seventh is pure content.

## Where the shape comes from

Nothing in `content_kinds.py` restates the schema. The examples, the field
names, the allowed enum values and the existing ids are all read out of the live
`GameData` file at run time — a registry that repeats the schema is a registry
that drifts from it, and then the model is being told to write content the
loader will reject. Each kind carries only what the repository cannot tell you
by looking: what the thing *means*.
