# Endless Frontier — Game Design Document

Version: 0.1 (pre-implementation)  
Date: 2026-06-01

---

## 1. Core Loops

### Primary loop (per session)

```
Open app
  └─ Calculate elapsed real-world time
  └─ Advance simulation N ticks
        ├─ Produce / consume resources per building
        ├─ Update health indicators
        └─ Run Storyteller (select events, apply effects)
  └─ Present events and world state to player
  └─ Player makes decisions (build, research, explore, respond to events)
  └─ Decisions are queued / applied to next tick(s)
Close app
```

### Secondary loop (per era)

```
Accumulate tech, population, stability milestones
  └─ Trigger era advancement
  └─ Unlock new buildings, event types, resources
  └─ Present major narrative milestone (LLM narrator, optional)
```

### Tertiary loop (exploration)

```
Send expedition to adjacent unknown region
  └─ Consume time + resources
  └─ Reveal biome + local resource deposits
  └─ Optionally discover ruins, threats or opportunities
  └─ Player decides: ignore / establish outpost / found city
```

---

## 2. World Model

### 2.1 Map

- Grid of **hexagonal tiles** (or square tiles as fallback for simplicity).
- The map is divided into **regions** — groups of ~7–20 tiles sharing a biome.
- At game start: one region fully revealed (the starting settlement region), surrounding regions unknown.
- Regions have:
  - `biome`: plains, forest, desert, tundra, mountains, coast, volcanic, …
  - `climate`: temperate / arid / cold / tropical
  - `resourceDeposits`: list of local resource types and quantities
  - `hazardLevel`: 0–10 (environmental danger)
  - `explorationState`: unknown / partially explored / fully explored
  - `settlements`: list of founded settlements in this region

### 2.2 Settlements / Cities

Each settlement is an independent economic and political unit with:

```
Settlement {
  id: UUID
  name: String
  regionId: UUID
  foundedTick: Int
  population: Int              // grows / shrinks each tick
  buildings: [BuildingInstance]
  storage: [ResourceType: Int] // local stockpile
  stats: SettlementStats       // see below
  productionQueue: [BuildOrder]
  tradeRoutes: [TradeRoute]    // to other settlements (future)
}

SettlementStats {
  stability: Float    // 0–100, collapse threshold < 10
  morale: Float       // 0–100
  growth: Float       // population growth rate modifier
  defense: Float      // military defense score
  pollution: Float    // 0–100, crises threshold > 80
}
```

### 2.3 Buildings

Buildings are data-defined:

```json
{
  "id": "farm_basic",
  "era": "early_settlement",
  "name": "Subsistence Farm",
  "cost": { "materials": 20 },
  "upkeep": { "workers": 2 },
  "production": { "food": 5 },
  "consumption": {},
  "effects": { "settlement.morale": +2 },
  "unlocks": ["farm_advanced"],
  "description": "A simple farm feeding a small community."
}
```

### 2.4 Global State

```
WorldState {
  tick: Int                           // monotonically increasing
  lastRealTimestamp: Date             // used to calculate elapsed ticks on open
  era: Era
  techProgress: [TechId: Bool]        // researched or not
  globalStats: GlobalStats
  exploredRegions: [RegionId]
  settlements: [Settlement]
  activeEvents: [ActiveEvent]         // events in progress (multi-tick)
  eventHistory: [HistoricalEvent]     // last N events for tension calc
}

GlobalStats {
  prosperity: Float       // 0–100
  stability: Float        // 0–100
  threatLevel: Float      // 0–100
  knowledgeOutput: Int    // per tick, feeds research
  influenceOutput: Int    // per tick, feeds diplomacy / expansion
}
```

---

## 3. Resource and Indicator System

### 3.1 Core Resources

Five global resources the player manages:

| Resource | Role | Produced by | Consumed by |
|---|---|---|---|
| **Food** | Sustains population | Farms, Hunters | Population upkeep, Feasts |
| **Materials** | Construction + industry | Quarries, Lumberyards, Mines | Building, Army |
| **Energy** | Powers advanced buildings | Windmills, Power Plants | Factories, Research labs |
| **Knowledge** | Drives research | Libraries, Schools | Tech tree nodes |
| **Influence** | Expansion + diplomacy | Trade Posts, Capitals | Founding cities, Alliances |

### 3.2 Health Indicators

These are derived stats, not stockpiles. They sit on a 0–100 scale with named bands:

| Indicator | Safe range | Warning | Crisis |
|---|---|---|---|
| Stability | 40–100 | 20–40 | 0–20 (rebellion / collapse) |
| Prosperity | 30–100 | 15–30 | 0–15 (poverty crisis) |
| Threat Level | 0–60 | 60–80 | 80–100 (invasion / disaster) |

### 3.3 Per-tick Update Algorithm

```
for each settlement:
  net_food    = sum(building.production.food)    – population * food_per_person
  net_materials = …
  net_energy  = …
  net_knowledge = …
  net_influence = …
  
  apply_deltas_to_storage()
  clamp_storage(min: 0, max: capacity)
  
  if food_storage < 0: trigger_famine_check()
  if energy_storage < 0: trigger_blackout_check()

recalculate_global_stats_from_settlements()
```

---

## 4. Tech and Era System

### 4.1 Eras

| # | Era Name | Flavour | Unlocks |
|---|---|---|---|
| 1 | Early Settlement | Stone age → subsistence farming | Basic buildings, first events |
| 2 | Ancient / Classical | Bronze → iron tools, early cities | Walls, trade, writing |
| 3 | Medieval | Feudalism, guilds, early trade | Knights, cathedrals, long-distance trade |
| 4 | Early Industrial | Steam, coal, factories | Factories, railways, pollution |
| 5 | Modern / Information | Electricity, internet | Data centers, global influence |
| 6 | (Optional) Near-Future | Renewables, AI, space | Off-world outposts, AI advisor |

Era advancement is triggered when the player meets all milestones for that era. Milestones are data-defined:

```json
{
  "era": "ancient",
  "milestones": [
    { "type": "tech_researched", "techId": "writing" },
    { "type": "tech_researched", "techId": "bronze_tools" },
    { "type": "global_stat", "stat": "prosperity", "min": 40 },
    { "type": "settlement_count", "min": 2 },
    { "type": "population_total", "min": 500 }
  ]
}
```

### 4.2 Tech Tree

The tech tree is a directed acyclic graph (DAG) defined in JSON:

```json
{
  "id": "writing",
  "name": "Writing",
  "era": "early_settlement",
  "requires": ["basic_tools"],
  "cost": { "knowledge": 50 },
  "effects": [
    { "type": "unlock_building", "buildingId": "library" },
    { "type": "modifier", "stat": "global.knowledgeOutput", "delta": 0.2 }
  ],
  "description": "Recording knowledge unlocks civilization's memory."
}
```

Research is automatic: accumulated `knowledge` points fill the active research node. The player queues one tech at a time.

---

## 5. Exploration and Expansion

### 5.1 Exploration

- Adjacent unknown regions can be **targeted for exploration**.
- An expedition costs resources (food + materials) and takes N ticks.
- Result: the region is revealed. A JSON "discovery" event fires, potentially spawning a storyteller event.
- Expedition cost and duration scale with distance from nearest founded settlement and biome hazard level.

### 5.2 Founding New Settlements

- A fully explored region can have an **outpost** founded in it (cheap, limited function).
- An outpost can be upgraded to a **city** after meeting local stability + population thresholds.
- Each new city:
  - increases global influence and prosperity over time,
  - introduces new biome-specific buildings and resources,
  - creates a supply-line vulnerability (if isolated, stability drops),
  - activates new storyteller event categories (e.g. border conflicts when 3+ cities exist).

---

## 6. Storyteller Engine

### 6.1 Tension Curve

Tension is a Float 0–100 computed each planner cycle (every N ticks):

```
tension = base_tension
        + threat_modifier         // global.threatLevel * 0.4
        - prosperity_modifier     // global.prosperity * 0.2
        + recent_disaster_spike   // sum of disaster events last 30 ticks * decay
        + resource_deficit_spike  // count of resources in deficit * 8
        - recent_boom_dampener    // positive events in last 20 ticks * 3
        + era_ramp                // era index * 5  (late game is inherently tenser)

tension = clamp(tension, 0, 100)
```

Tension drives event weight multipliers:

| Tension band | Disaster weight | Opportunity weight | Flavor weight |
|---|---|---|---|
| 0–30 (calm) | 0.5× | 1.5× | 2× |
| 31–60 (active) | 1× | 1× | 1× |
| 61–80 (stressed) | 1.8× | 0.6× | 0.5× |
| 81–100 (crisis) | 3× | 0.3× | 0.1× |

### 6.2 Event Templates

Events are defined in JSON (see `docs/data-schemas/events.json` for schema). Each template has:

```json
{
  "id": "drought",
  "type": "disaster",
  "name": "Drought",
  "era": ["early_settlement", "ancient", "medieval"],
  "weight": 10,
  "conditions": [
    { "stat": "global.threatLevel", "min": 0 },
    { "stat": "settlement[any].food_storage", "max": 200 },
    { "worldFlag": "biome:plains", "present": true }
  ],
  "effects": [
    { "type": "resource_delta", "resource": "food", "delta": -150, "duration_ticks": 20 },
    { "type": "stat_delta", "stat": "settlement[all].morale", "delta": -10 }
  ],
  "narrative_hint": "A prolonged dry spell withers crops across the plains.",
  "choices": [
    {
      "id": "pray",
      "label": "Hold a prayer ceremony",
      "cost": { "influence": 10 },
      "effect": { "stat": "settlement[all].morale", "delta": +5 }
    },
    {
      "id": "ration",
      "label": "Implement food rationing",
      "cost": {},
      "effect": { "stat": "settlement[all].morale", "delta": -5, "resource": "food", "delta_pct": 0.2 }
    }
  ],
  "cooldown_ticks": 100
}
```

Event types:
- **disaster** — damages resources or stats
- **threat** — introduces an ongoing danger (requires resolution)
- **opportunity** — bonus if player acts
- **quest** — multi-step chain with prerequisites and rewards
- **flavor** — purely narrative, no mechanical effect

### 6.3 Planner Algorithm

Runs every `PLANNER_INTERVAL` ticks (configurable, default 10):

```
1. Compute tension T
2. Filter all event templates by:
   a. era match
   b. conditions satisfied against current WorldState
   c. cooldown not active
3. Weight each candidate: effective_weight = template.weight × tension_modifier(T, type)
4. Roll major event slot:
   - if T > 40: weighted random pick from disasters + threats + opportunities
   - if T ≤ 40: weighted random pick from opportunities + quests
5. Roll 0–3 minor flavor events (low weight, no conditions except era)
6. Apply effects of selected events to WorldState
7. Record to eventHistory
```

---

## 7. LLM Narrator (Optional Layer)

The LLM layer is **entirely optional**. The simulation and storyteller must work without it.

### 7.1 When it fires

After the storyteller selects events for a planner cycle, if an LLM is available (local or remote), a compact snapshot is assembled and sent to the LLM.

### 7.2 Input schema

```json
{
  "snapshot": {
    "era": "medieval",
    "tick": 4200,
    "prosperity": 62,
    "stability": 44,
    "threatLevel": 71,
    "population": 1840,
    "settlementCount": 3,
    "resourceLevels": {
      "food": "adequate",
      "materials": "surplus",
      "energy": "deficit",
      "knowledge": "adequate",
      "influence": "low"
    }
  },
  "recentEvents": [
    { "id": "border_skirmish", "tick": 4195, "type": "threat" },
    { "id": "harvest_festival", "tick": 4180, "type": "flavor" }
  ],
  "currentEvents": [
    {
      "id": "plague_outbreak",
      "type": "disaster",
      "narrative_hint": "A sickness spreads through the eastern settlement."
    }
  ],
  "prompt_role": "narrator"
}
```

### 7.3 Output schema

```json
{
  "chronicle": "Week 42, Third Era. The eastern province of Aldenmere has fallen into shadow. A fever, they call it the Grey Breath, has claimed seventeen souls in as many days...",
  "advisorComment": "Chancellor, our grain stores grow thin as the sick cannot work the fields. I counsel swift action.",
  "flavorDetails": {
    "eventName": "The Grey Breath",
    "affectedSettlementNickname": "Aldenmere"
  }
}
```

Rules for the LLM layer:
- The LLM **never writes directly to WorldState**. All world changes go through deterministic event effects.
- Output is purely narrative / cosmetic.
- If the LLM is unavailable, the game uses `event.narrative_hint` as fallback text.
- Input snapshots are capped at ~500 tokens to keep cost low.

---

## 8. Failure Modes and Edge Cases

### 8.1 Runaway growth

**Symptom**: player stockpiles all resources, tension stays near 0, nothing interesting happens.

**Mitigations**:
- Tension formula includes an era ramp — later eras baseline higher tension.
- High prosperity triggers "golden age" events that introduce new ambitions (costly mega-projects, exploration pressure).
- Flavor event weights at low tension fill the vacuum; some introduce new quests.

### 8.2 Death spirals

**Symptom**: one crisis (food shortage) cascades into morale drop → rebellion → defense drop → invasion → collapse.

**Mitigations**:
- Storyteller enforces disaster cooldowns (no two disasters within N ticks).
- Crisis events offer at least one choice that partially mitigates damage.
- "Last resort" safety valve event fires if stability < 10 (mercy mechanic: refugee aid, treaty offer, etc.).

### 8.3 Boring states

**Symptom**: player has done everything interesting for this era but hasn't hit era milestones yet.

**Mitigations**:
- Era milestone tracker surfaces prominently in UI (next milestone, progress bar).
- Storyteller emits "opportunity" events pointing at unmet milestones when tension is low and era progress is stalled.

### 8.4 Offline time abuse

**Symptom**: player leaves game for weeks; returning with enormous resource surpluses collapses all challenge.

**Mitigations**:
- Storage capacity caps are hard (cannot exceed building-defined maximum).
- Offline ticks apply upkeep (maintenance, decay) in addition to production.
- Planner runs offline as normal; events accumulate and are presented as a "while you were away" summary on next open.
- Maximum offline catchup can be capped (e.g., 30 days worth of ticks) to prevent exploitation.

### 8.5 Multi-city complexity explosion

**Symptom**: managing 8+ cities becomes cognitively overwhelming.

**Mitigations**:
- Settlements default to an **automation policy** (set once, runs automatically).
- Player only manually intervenes on events, research, and expansion decisions.
- City overview screen shows only cities in trouble.

---

## 9. Data-driven design principles

- All game content (buildings, techs, events, eras, biomes) lives in **JSON files** under `GameData/`.
- The simulation engine reads these at startup and builds in-memory registries.
- Adding a new building or event requires zero code changes.
- Balance iteration (tweak production numbers, event weights, tension formula constants) is done by editing JSON / constants file, not code.
