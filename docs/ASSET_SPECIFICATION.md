# Endless Frontier — Asset Specification

**Version**: 1.0  
**Date**: 2026-06-01  
**Project**: Endless Frontier (iOS colony simulator)  
**Target platforms**: iPhone, iPad  

---

## 1. Visual Direction & Art Style

### 1.1 Core Direction

**Isometric colonist-driven settlement with procedural biome art.**

Endless Frontier is a deterministic, persistent civilization builder in the spirit of RimWorld and Dwarf Fortress. The visual language must:
- Feel **hand-crafted and lived-in**, not template-like
- Support **individual colonist silhouettes** (short 2D character portraits)
- Scale across **eras** (stone tools → steam engines → satellites) without style breaks
- Work **on both phone and iPad** with clarity at small sizes (1×1 icon grid cells)
- Evoke **geographic richness**: each biome should feel distinct and exploreable

### 1.2 Aesthetic Choice

**Stylized iso-cartographic with muted, grounded tones.**

- **Not**: flat design, glossy app UI, minimalist line art, neon gradients
- **Yes**: ink-and-watercolor texture, weathered materials, earth tones with pop-of-color accents, hand-drawn linework (AI-assisted but character-evident)
- **Inspiration**: old exploration maps, natural history engravings, Stardew Valley's muted palette, Kenney's isometric asset packs (but more personality)
- **Colonist portraits**: stylized 2D head-and-shoulders (inspired by classic D&D character art), monochrome base + color accent (mood/status ring)

### 1.3 Tone

- **Hopeful but precarious**: your colony is a foothold in a dangerous world
- **Earned progression**: early stone tools look primitive; steam engines should feel like a breakthrough
- **Personality in every asset**: a farm is not generic; it's *your* farm, with distinct patterns and quirks

---

## 2. Color Palette

### 2.1 Design Tokens (CSS Custom Properties)

```css
:root {
  /* --- Neutrals (landscape base) --- */
  --color-soil-dark: #3d3d2f;      /* Earth, foundations */
  --color-soil-light: #8b8b73;     /* Sand, dried clay */
  --color-stone: #6d6d5d;          /* Gray stone, quarries */
  --color-bark: #5a4a3a;           /* Wood, tundra bark */
  --color-snow: #e8e8e0;           /* Snow, light surfaces */
  
  /* --- Greens (vegetation tiers) --- */
  --color-plant-dark: #2d5a2d;     /* Deep forest */
  --color-plant-mid: #5a8a4a;      /* Healthy crops */
  --color-plant-light: #9ab87a;    /* Spring growth, light meadow */
  --color-grass: #7a9a5a;          /* Grassland */
  
  /* --- Resource accents (signal player attention) --- */
  --color-food: #d4a84a;           /* Warm gold — wheat, harvest */
  --color-materials: #9a7a6a;      /* Tan-brown — wood, stone */
  --color-energy: #c85a3a;         /* Warm rust-orange — fire, wind */
  --color-knowledge: #5a7aaa;      /* Deep blue — books, stars */
  --color-influence: #8a5aaa;      /* Soft purple — trade, diplomacy */
  
  /* --- Status colors --- */
  --color-success: #6a9a4a;        /* Prosperity green */
  --color-warning: #ca8a3a;        /* Tension orange */
  --color-danger: #c85a4a;         /* Crisis red */
  --color-neutral: #7a8a9a;        /* Stability gray */
  
  /* --- Water & sky --- */
  --color-water-shallow: #6aa8c8;  /* Coastal shallows */
  --color-water-deep: #4a7a9a;     /* Ocean depth */
  --color-sky-dawn: #e8a8c8;       /* Early light */
  --color-sky-day: #a8d8f0;        /* Clear sky */
  --color-sky-dusk: #d89a6a;       /* Golden hour */
  
  /* --- Biome overlays --- */
  --overlay-desert: rgba(212, 168, 74, 0.15);
  --overlay-forest: rgba(45, 90, 45, 0.1);
  --overlay-tundra: rgba(232, 232, 224, 0.2);
  --overlay-mountains: rgba(109, 109, 93, 0.15);
  --overlay-coast: rgba(106, 168, 200, 0.1);
}
```

### 2.2 Palette Usage

| Biome | Primary | Secondary | Accent |
|-------|---------|-----------|--------|
| **Plains** | --color-grass | --color-soil-light | --color-food (gold) |
| **Forest** | --color-plant-dark | --color-bark | --color-materials (tan) |
| **Desert** | --color-soil-light | --color-stone | --color-energy (orange) |
| **Tundra** | --color-snow | --color-bark | --color-neutral (gray) |
| **Mountains** | --color-stone | --color-soil-dark | --color-materials (tan) |
| **Coast** | --color-water-shallow | --color-grass | --color-influence (purple) |

**Rule**: Every biome uses at least one soil/stone/sky neutral from column 2.1, then layers with biome-specific overlay. No biome should look bright or candy-colored.

---

## 3. Typography

### 3.1 Font Choices

| Use | Font | Rationale |
|-----|------|-----------|
| **Headline (era names, major events)** | Georgia or equivalent serif | Authority, timelessness |
| **Body (descriptions, tooltips)** | System font (SF Pro or Segoe UI) | Clarity, small-size legibility on mobile |
| **UI labels (resource counts, stat labels)** | System font (monospace variant if available) | Scannable, precise numbers |
| **Colonist names, flavor text** | System font (italic for flavor) | Readable at any size |

### 3.2 Sizing Scale

- **Era title**: 28pt (iPad) / 20pt (iPhone)
- **Settlement name**: 18pt (iPad) / 14pt (iPhone)
- **Building/resource labels**: 14pt (iPad) / 12pt (iPhone)
- **Small UI text (tooltips)**: 12pt (iPad) / 10pt (iPhone)
- **Colonist name**: 14pt (iPad) / 12pt (iPhone)

### 3.3 Line Heights

- **Headlines**: 1.2
- **Body text**: 1.4
- **Labels**: 1.0 (tight, scannable)

---

## 4. Icon Specifications

### 4.1 Grid and Sizing

- **Grid basis**: 64×64 pixels (1× base)
- **Actual icon sizes in-game**:
  - **Building slots** (hex map): 96×96 (1.5×)
  - **Resource counter icons**: 32×32 (0.5×)
  - **Tech tree nodes**: 64×64 (1×)
  - **Settlement stat badges**: 48×48 (0.75×)
  - **Colonist portrait**: 64×64 (1×, with optional 3-step mood indicator around border)

### 4.2 Design Rules

1. **Isometric view** (top-down 45° angle, cabinet projection)
   - Buildings and terrain features drawn from above-left
   - Shadow/depth cues via darker bottom edge
   - No perspective or vanishing point distortion

2. **Stroke weight**: 2–3 pixels at 1× scale (scales up on iPad)
3. **No anti-alias halo**: crisp pixels, slight feather only where needed
4. **Color**: use the biome palette; avoid pure black (use --color-soil-dark or --color-stone)
5. **Transparency**: PNG with alpha. Flat background (no checkerboard shadow on ground)
6. **Outline**: +1px darker shade for definition against bright backgrounds

### 4.3 Construction Progression

Buildings should have 3 variants:
1. **Foundation** (under construction, half-opacity, outline only)
2. **Active** (finished, full color, shadow visible)
3. **Damaged** (reduced saturation, warning tint, stress cracks)

---

## 5. Complete Icon List

### 5.1 Buildings (11 + 3 state variants = 36 total)

#### Early Settlement Era

| Building ID | Name | Isometric Form | Key Color | Notes |
|---|---|---|---|---|
| `hut` | Dwelling Hut | Low peaked roof (straw/thatch), doorway | --color-soil-light | Morale boost; cluster in settlements |
| `farm_basic` | Subsistence Farm | Patchwork field grid (4 squares), wooden fence border | --color-food | Golden wheat patches |
| `lumberyard` | Lumberyard | Log stack (3-4 logs in pyramid), tree stump beside, axe | --color-materials | Browns and tans |
| `hunters_lodge` | Hunter's Lodge | Small wooden structure, hanging pelts, spear rack | --color-energy | Russet, bone-white accents |
| `quarry` | Stone Quarry | Pit with stepped layers, 2–3 stone blocks stacked nearby, pickaxe | --color-stone | Grays and browns |
| `library` | Library | Small domed or arched building, scroll stacks visible, scrolls on floor | --color-knowledge | Warm whites, spine colors (gold/purple) |

#### Ancient Era

| Building ID | Name | Isometric Form | Key Color | Notes |
|---|---|---|---|---|
| `farm_advanced` | Irrigated Farm | Field grid (6 squares), irrigation channel threading through, water shimmer | --color-food | Brighter greens; water pale blue |
| `windmill` | Windmill | Tall tower with 4-blade windmill sail, rotating indication (slight tilt), wooden framework | --color-energy | Cream tower, brown wood, orange/rust accent on hub |
| `trade_post` | Trade Post | Covered marketplace pavilion, 2–3 trader silhouettes, bales/goods stacked | --color-influence | Striped cloth awning (purple/tan) |

#### Medieval Era

| Building ID | Name | Isometric Form | Key Color | Notes |
|---|---|---|---|---|
| `school` | School | Larger building (bell tower optional), children silhouettes in windows, open door with light spill | --color-knowledge | Stone or timber-framed, blue/gold roof tile accents |

**For future eras (Early Industrial, Modern, Near Future):**
- Add factory, power plant, data center, research facility icons on same grid
- Maintain era visual language (e.g., factories have smokestacks with optional smoke puffs)

### 5.2 Resources (5 total)

| Resource ID | Icon Concept | Key Color | Symbol/Silhouette |
|---|---|---|---|
| `food` | Wheat sheaf or loaf of bread | --color-food | Stylized grain bundle, slightly angled |
| `materials` | Stack of wood planks or stone blocks | --color-materials | 3–4 planks stacked, or cubic block pile |
| `energy` | Flame or wind turbine blade | --color-energy | Curved flame or single blade silhouette |
| `knowledge` | Open book or quill pen | --color-knowledge | Book pages facing front, or quill with ink drop |
| `influence` | Crowned coin or merchant badge | --color-influence | Coin with emblem, or merchant scale |

### 5.3 Eras (6 icons + 1 milestone badge)

| Era ID | Icon Concept | Key Color | Visual progression |
|---|---|---|---|
| `early_settlement` | Stone axe + pestle | --color-stone | Crude, rough-hewn |
| `ancient` | Bronze helmet + scroll | --color-knowledge | Refined edges, symmetrical |
| `medieval` | Crown + sword | --color-energy | Ornate, pointed arches |
| `early_industrial` | Gear + coal lump | --color-energy | Mechanical, industrial geometry |
| `modern` | Light bulb + computer chip | --color-knowledge | Clean lines, technical |
| `near_future` | Satellite + circuit node | --color-influence | Futuristic, connected nodes |
| `era_milestone` | Radiant star badge | --color-success (gold) | Glow/halo effect, celebratory |

### 5.4 UI/Status Icons (18 total)

#### Health & Stability

| ID | Name | Icon | Color |
|---|---|---|---|
| `stability_safe` | Stability OK | Green shield outline | --color-success |
| `stability_warning` | Stability Warning | Yellow shield outline | --color-warning |
| `stability_critical` | Stability Critical | Red shield outline | --color-danger |
| `morale_happy` | Morale High | Smiley face | --color-success |
| `morale_content` | Morale Neutral | Straight face | --color-neutral |
| `morale_sad` | Morale Low | Frown face | --color-danger |

#### Resources (low stock indicator)

| ID | Name | Icon | Color |
|---|---|---|---|
| `food_empty` | No Food | Empty bowl | --color-danger |
| `materials_empty` | No Materials | Empty basket | --color-danger |
| `energy_empty` | No Energy | Extinguished lamp | --color-danger |

#### Actions & States

| ID | Name | Icon | Color |
|---|---|---|---|
| `under_construction` | Building Under Construction | Scaffold/blueprint grid | --color-neutral |
| `damaged` | Building Damaged | Cracked foundation | --color-warning |
| `event_disaster` | Disaster Event | Storm cloud with lightning bolt | --color-danger |
| `event_opportunity` | Opportunity Event | Star or gift box | --color-success |
| `tech_researching` | Tech In Progress | Beaker or test tube | --color-knowledge |
| `tech_complete` | Tech Complete | Checkmark in circle | --color-success |

### 5.5 Colonist Status Rings (4 variants)

Colonist portrait frame/ring (drawn around the 64×64 portrait):

| Mood | Outer Ring Color | Symbol |
|---|---|---|
| **Content** | --color-success (green) | None, solid ring |
| **Neutral** | --color-neutral (gray) | None, solid ring |
| **Upset** | --color-warning (orange) | Small frown mark at 6 o'clock |
| **Breaking/Critical** | --color-danger (red) | Lightning bolt or spiral at 6 o'clock |

### 5.6 Biome Terrain Tiles (6 base variants + 3 variants each = 24 total)

Each biome needs:
1. **Base grass/ground** — flat, featureless
2. **Feature variant 1** — single small rock, tree, or flora
3. **Feature variant 2** — water, cliff edge, or landmark silhouette

| Biome | Tile 1 (Base) | Tile 2 (Feature) | Tile 3 (Landmark) |
|---|---|---|---|
| Plains | Grass with slight slope lines | Single wildflower or field marker | Lone tree or wooden sign |
| Forest | Dense forest floor (brown + green) | Felled log or shroom circle | Tall sentinel tree |
| Desert | Sand with wind ripples | Cactus or dune formation | Desert rock outcrop |
| Tundra | Snow-covered ground | Ice formation or hardy shrub | Glacier edge or standing stone |
| Mountains | Rocky slope (grays/browns) | Boulder cluster | Mountain peak silhouette |
| Coast | Sand transitioning to water | Driftwood log | Lighthouse silhouette |

---

## 6. Biome Art Direction (Midjourney Prompts)

### 6.1 General Parameters for All Prompts

```
--style raw
--niji off (photorealistic, not anime)
--ar 1:1 (square, 64×64 pixel output ready)
--q 2 (high quality)
```

### 6.2 Per-Biome Prompts

#### Plains

```
isometric top-down view, lush green grassland, rolling hills with gentle slope,
natural light, soft shadows, watercolor painting style, earth tones with golden
wheat accents, weathered wooden fence segments, scattered wildflowers, calm
atmosphere, muted palette, no people, detailed ground texture, --style raw --ar 1:1 --q 2
```

**Render target**: 6–8 tile variants (grass base, flower patch, field marker, slope variant, water edge, rock cluster)

#### Forest

```
isometric top-down view, dense dark green forest, thick tree canopy, forest
floor with fallen logs and brown leaf litter, natural dappled sunlight, ink
illustration with watercolor accents, rich greens and dark browns, sturdy tree
trunks in background, mysterious but safe feeling, hand-drawn character, --style raw --ar 1:1 --q 2
```

**Render target**: 6–8 variants (pine forest, mixed deciduous, felled log, forest clearing, mushroom circle, stream edge)

#### Desert

```
isometric top-down view, vast sandy desert, dunes with subtle contour lines,
sparse vegetation, cactus plants, warm golden-orange sand, hard shadows from
bright sunlight, illustrated atlas map style, weathered and arid, hand-painted
texture, high hazard feeling, --style raw --ar 1:1 --q 2
```

**Render target**: 6–8 variants (open sand, dune crest, cactus cluster, rock outcrop, water oasis, salt flat)

#### Tundra

```
isometric top-down view, arctic tundra, snow-covered ground, hardy shrubs and
grasses poking through, ice formations, pale blue-white palette, cold hard light,
natural history engraving style combined with muted watercolor, bleak but detailed,
geological appearance, hostile environment, --style raw --ar 1:1 --q 2
```

**Render target**: 6–8 variants (bare snow, ice ridge, lichen patch, shrub clump, glacier edge, standing stone)

#### Mountains

```
isometric top-down view, rocky mountain slope, gray and brown stone outcrops,
sparse alpine vegetation, steep terrain with contour shading, geological survey
map illustration, hand-drawn rock texture, strong shadows, formidable and mineral-rich,
natural light from upper left, --style raw --ar 1:1 --q 2
```

**Render target**: 6–8 variants (rocky base, boulder cluster, cliff face, sparse grass, mountain stream, ore vein hint)

#### Coast

```
isometric top-down view, coastal beach, sand meeting shallow water, driftwood
logs, seaweed, rocky formations, blue-green water with slight shimmer, aged
maritime map illustration, soft greens and blues, weathered appearance, safe harbor
feeling, waves indicated by gentle lines, --style raw --ar 1:1 --q 2
```

**Render target**: 6–8 variants (sandy beach, water edge, driftwood, rock pool, cliff formation, shipwreck hint)

### 6.3 Midjourney Workflow

1. **Generate base** with biome prompt
2. **Upscale 2×** to 128×128 (can downscale to 64×64 without quality loss)
3. **Crop to clean 1:1 square** (remove any gradient/border)
4. **Export as PNG** with transparent background (use Photoshop/Figma to cut out white)
5. **Iterate**: prompt variations like "add more texture", "remove people", "darker shadows" to create the 6–8 tile variants per biome

---

## 7. Icon Design Specifications (Recraft.ai / Midjourney)

### 7.1 Universal Style Prompt (For Consistency)

**Use this as a prefix for all icon Midjourney/Recraft prompts:**

```
isometric pixel-art meets watercolor illustration, 64×64 grid basis, top-down
45-degree cabinet projection, weathered natural materials (wood, stone, earth),
earth-tone palette with gold/orange/blue accents, no pure black (use soil-dark),
slight hand-drawn linework (AI assisted but character evident), 2–3 pixel stroke
weight, strong shadow on bottom edge (depth cue), no reflections or glossiness,
aged map illustration style, detailed texture but readable at small sizes,
--style raw --ar 1:1 --q 2
```

### 7.2 Building Icon Template

**Generic building prompt structure:**

```
[UNIVERSAL STYLE PROMPT]

subject: [BUILDING NAME], isometric wood/stone structure, [SPECIFIC FEATURES],
visible door and roof line, casting shadow to bottom right, located in [BIOME],
no surrounding terrain (isolated on white ground), material accent color [--color-*],
historically authentic [ERA] design element.
```

**Example: Hut**

```
[UNIVERSAL STYLE PROMPT]

subject: dwelling hut, small isometric wooden structure with peaked thatch roof,
single open door with warm light spill, sitting on bare earth, casting shadow to
bottom-right, early settlement era, warm tan and brown, no people visible, nestled
feeling.
```

### 7.3 Resource Icon Template

```
[UNIVERSAL STYLE PROMPT]

subject: [RESOURCE NAME] icon, simplified silhouette of [OBJECT], roughly 32×32
within 64×64 canvas (centered), primary color [--color-*], secondary shading only,
no background, symbol-like clarity, instantly readable at small sizes.
```

**Example: Food**

```
[UNIVERSAL STYLE PROMPT]

subject: food resource icon, wheat sheaf or grain bundle, angled 45 degrees,
golden-tan color, simplified leaf shapes, minor brown shading, very clear silhouette,
no background.
```

### 7.4 Era Icon Template

```
[UNIVERSAL STYLE PROMPT]

subject: [ERA NAME] era badge, combining 2–3 symbolic objects ([OBJECT 1] + [OBJECT 2]),
arranged in isometric composition, roughly 48×48 centered in 64×64, primary color [--color-*],
representing technological leap to [ERA], historical significance evident.
```

**Example: Medieval**

```
[UNIVERSAL STYLE PROMPT]

subject: medieval era badge, ornate crown + sword point, interlocked composition,
stone background hint, rich golds and deep blues, fortress-like feeling, 48×48
in 64×64 frame, centered.
```

### 7.5 Colonist Portrait Template

**Portrait should be 64×64, head-and-shoulders, stylized 2D character art:**

```
[UNIVERSAL STYLE PROMPT]

subject: colonist portrait, stylized 2D character head-and-shoulders, aged adventure
illustration style, neutral expression, simple clothing [ERA]-appropriate, solid
background color [BIOME] tint, no gradient, monochrome face with minimal color accent
(cheek or clothing), instantly expressive and memorable, 64×64 exactly.
```

**Generate 8–10 variations** (different ages, genders, expressions, clothing patterns) to randomize in-game.

---

## 8. Design System & Consistency Rules

### 8.1 Stroke and Shadow

- **All building icons**: 2–3px stroke weight, darker shade (soil-dark or stone)
- **All icons shadow**: bottom-right edge darkened by 20–30% for depth
- **No harsh black outlines**: use biome-specific shadow colors

### 8.2 Transparency & Edges

- **PNG with alpha channel** (transparent background)
- **Feather edges by 0–1 pixel** where needed to soften harsh lines
- **No white halo or drop shadow** outside the icon boundary

### 8.3 Biome Color Consistency

| Biome | Primary | Secondary | Accent |
|-------|---------|-----------|--------|
| Plains | --color-grass | --color-soil-light | --color-food |
| Forest | --color-plant-dark | --color-bark | --color-materials |
| Desert | --color-soil-light | --color-stone | --color-energy |
| Tundra | --color-snow | --color-bark | --color-neutral |
| Mountains | --color-stone | --color-soil-dark | --color-materials |
| Coast | --color-water-shallow | --color-grass | --color-influence |

**Rule**: If building icon appears in multiple biomes, use the primary color of its home biome, not the player's current biome.

### 8.4 Asset Naming Convention

```
{category}_{id}_{variant}.png

Examples:
- building_hut_active.png
- building_hut_foundation.png
- building_hut_damaged.png
- resource_food.png
- era_medieval.png
- colonist_portrait_001.png
- terrain_plains_base.png
- terrain_forest_log.png
- ui_stability_warning.png
```

### 8.5 Icon Export Checklist

- [ ] 64×64 base size (or 1.5× for buildings = 96×96)
- [ ] PNG format with alpha transparency
- [ ] Isometric 45° projection (top-down-left view)
- [ ] 2–3px stroke weight at 1× scale
- [ ] Shadow on bottom-right edge
- [ ] Biome palette colors applied correctly
- [ ] No pure black (use --color-soil-dark or --color-stone)
- [ ] Readable at 32×32 (half size)
- [ ] Consistent with other icons in category
- [ ] Filename matches convention

---

## 9. Implementation Roadmap

### Phase 1: Foundation (Weeks 1–2)

1. **Finalize color palette** in code (CSS custom properties or Swift Color structs)
2. **Commission/generate terrain tiles** (Midjourney + Recraft)
   - 6 biomes × 3 variants = 18 base tiles
   - Generate as 128×128, downscale to 64×64
3. **Create building icons** (6 Early Settlement + 3 Ancient + 1 Medieval = 10 buildings)
   - × 3 states (active, foundation, damaged) = 30 total icon files
4. **Create resource icons** (5 resources × 1 = 5)
5. **Create era badges** (6 eras × 1 = 6)

### Phase 2: Polish & Expansion (Weeks 3–4)

6. **Colonist portrait generator** (seed-based random avatar from 8–10 base templates)
7. **UI status icons** (18 small icons for health, morale, resources, actions)
8. **Color mood ring system** for colonist frames (4 variants)
9. **Quality pass**: upscale Midjourney outputs, crop, export, test in SwiftUI
10. **Build documentation**: asset registry JSON + loading code

### Phase 3: Future Eras (Weeks 5+)

11. Extend buildings to Industrial, Modern, Near Future eras
12. Add dungeon/ruin/anomaly terrain variants
13. Biome-specific colonist costume variants

---

## 10. Asset Delivery Format

### 10.1 Directory Structure

```
Core/Sources/EndlessFrontierCore/Resources/Assets/
├── Icons/
│   ├── Buildings/
│   │   ├── building_hut_active.png
│   │   ├── building_hut_foundation.png
│   │   ├── building_hut_damaged.png
│   │   ├── ... (30 total: 10 buildings × 3 states)
│   ├── Resources/
│   │   ├── resource_food.png
│   │   ├── resource_materials.png
│   │   ├── ... (5 total)
│   ├── Eras/
│   │   ├── era_early_settlement.png
│   │   ├── ... (6 total)
│   ├── UI/
│   │   ├── ui_stability_safe.png
│   │   ├── ... (18 total)
│   └── Colonists/
│       ├── colonist_portrait_001.png
│       ├── ... (10+ portraits)
├── Terrain/
│   ├── Plains/
│   │   ├── terrain_plains_base.png
│   │   ├── terrain_plains_flower.png
│   │   ├── terrain_plains_marker.png
│   │   └── ... (6–8 variants)
│   ├── Forest/
│   │   └── ... (6–8 variants)
│   ├── Desert/
│   ├── Tundra/
│   ├── Mountains/
│   └── Coast/
└── AssetRegistry.json  # Manifest of all assets
```

### 10.2 AssetRegistry.json Schema

```json
{
  "version": "1.0",
  "assets": {
    "buildings": [
      {
        "id": "hut",
        "era": "early_settlement",
        "name": "Dwelling Hut",
        "icon": "building_hut_active.png",
        "iconFoundation": "building_hut_foundation.png",
        "iconDamaged": "building_hut_damaged.png",
        "primaryColor": "--color-soil-light"
      }
    ],
    "resources": [
      {
        "id": "food",
        "name": "Food",
        "icon": "resource_food.png",
        "color": "--color-food"
      }
    ],
    "eras": [
      {
        "id": "early_settlement",
        "name": "Early Settlement",
        "icon": "era_early_settlement.png",
        "color": "--color-stone"
      }
    ],
    "terrain": {
      "plains": ["terrain_plains_base.png", "terrain_plains_flower.png", ...],
      "forest": [...],
      "desert": [...],
      "tundra": [...],
      "mountains": [...],
      "coast": [...]
    },
    "colonists": {
      "portraitBases": ["colonist_portrait_001.png", ...],
      "moodRings": {
        "content": "ring_mood_content.png",
        "neutral": "ring_mood_neutral.png",
        "upset": "ring_mood_upset.png",
        "breaking": "ring_mood_breaking.png"
      }
    }
  }
}
```

---

## 11. Visual Brand Summary

| Element | Choice | Reason |
|---------|--------|--------|
| **Color palette** | Muted earth tones (soil, bark, grass) + resource accents (gold, blue, purple) | Grounded, natural, biome-specific |
| **Art style** | Isometric watercolor + ink illustration | Exploreable, detailed, hand-crafted feel |
| **Colonist design** | Stylized 2D portraits (D&D-inspired) + mood ring | Memorable, personal, immediately expressive |
| **Typography** | Serif headlines (Georgia), system font body | Authority + clarity, mobile-friendly |
| **Iconography** | 64×64 grid, 45° isometric, 2–3px stroke | Readable at small sizes, consistent across eras |
| **Animation principle** | Minimal, purposeful (dock bobbing, resource glow, mood flash) | No distraction from gameplay |

---

## 12. Quick Reference Checklists

### Icon Audit Checklist

- [ ] All 11 building icons generated (+ 3 states each = 33 icons)
- [ ] All 5 resource icons generated
- [ ] All 6 era badges generated
- [ ] All 18 UI status icons generated
- [ ] 10+ colonist portrait variations
- [ ] 4 mood ring variants
- [ ] All terrain tiles for each biome (6 biomes × 6–8 variants = 36–48)
- [ ] Consistency pass (colors, stroke weight, shadows)
- [ ] Smallest-size readability test (32×32, 48×48)
- [ ] AssetRegistry.json populated and validated

### Color Consistency Checklist

- [ ] No pure black in any icon (use --color-soil-dark or biome-specific shade)
- [ ] Each biome's palette is distinct (Plains ≠ Desert ≠ Forest visually)
- [ ] Resource accents are highly visible against background
- [ ] Status colors (success/warning/danger) work on all biome backgrounds
- [ ] No white halo or unintended transparency artifacts

### Style Consistency Checklist

- [ ] All icons use same isometric projection (top-down-left, no perspective distortion)
- [ ] All icons have bottom-right shadow for depth
- [ ] Stroke weight consistent within category (buildings same weight, resources same weight)
- [ ] Hand-drawn feel evident but not sloppy (AI assisted + human touch)
- [ ] Eras visually progress (stone → bronze → medieval → steam → modern)

---

## Appendix A: Biome Personality

**Visual flavor to infuse into terrain tiles and buildings per biome:**

- **Plains**: golden wheat, open sky, wooden fences, wind-swept grass
- **Forest**: dark canopy, fallen logs, mushroom circles, dappled light, mystery
- **Desert**: endless sand, harsh shadows, sparse cacti, heat shimmer, danger
- **Tundra**: ice crystals, hardy shrubs, pale light, harsh winds, isolation
- **Mountains**: rock formations, altitude, ore glints, fortress-like, majesty
- **Coast**: driftwood, shallow water, salt spray, seabirds, trade routes

---

## Appendix B: Planned Extended Biomes

These icons can be designed in Phase 2:

- **Volcanic**: lava flows, ash, obsidian, sulfur vents
- **Swamp**: murky water, mangroves, insects, rot/decay
- **Jungle**: dense canopy, ruins, predators, humidity
- **Frozen lake**: ice, cracks, fish-eye view, eerie calm
- **Badlands**: colorful rock layers, erosion, fossils, alien landscape

Each would follow the same template: 6–8 terrain variants + biome-specific buildings.

---

**Document Version**: 1.0  
**Last Updated**: 2026-06-01  
**Next Review**: After Phase 1 asset delivery (2026-06-15)
