# Deep Descent — Project Guide

First-person atmospheric submarine **horror game** for Roblox (Luau). Player wakes as the sole survivor in a crashed, flooding submarine on the ocean floor. A blind, sound-hunting creature stalks the corridors. Explore 9 sections, restore power, manage a 4-slot inventory, uncover the story, and reach one of 8 endings.

- **Genre:** Horror / Survival / Puzzle — **first-person only**, 13+
- **Design doc (source of truth):** `C:\Users\Razvan\Desktop\DeepDescent_GameDesignDocument.docx` (full GDD + 12-phase implementation plan)
- **Status:** Pre–Phase 1. Project directory is empty; nothing built yet.

## Core design philosophy (do not violate)
- Atmosphere over jump scares — fear comes from *not knowing*.
- Every mechanic serves the narrative (flooding *is* the story, not just a timer).
- Player agency — multiple valid approaches to every problem.
- **Sound is 50% of the horror.**
- Respect the player — no hand-holding, environmental storytelling only.
- When unsure about a mechanic, ask: *does this add tension or frustration?* Only add tension.

## Build workflow — Weppy MCP (NOT Rojo)
This project is built through **Weppy** (`weppy-roblox-mcp`), an MCP server that drives a **live Roblox Studio session** directly. Registered for this project via `.mcp.json` at the repo root.

**To work, a session needs:** (1) Claude Code restarted in this folder so the MCP server loads + is approved; (2) Roblox Studio open with the DeepDescent place + Weppy plugin connected. Verify connection at the dashboard: http://localhost:3002.

**Tool groups** (see `~/.claude/plugins/marketplaces/hope1026-roblox-mcp/plugins/weppy-roblox-mcp/skills/weppy-roblox-mcp-guide/references/mcp-actions.md` for exact action names/params):
- `query_instances` — read the Studio tree (get/children/find/search).
- `mutate_instances` — create/delete/clone/move/rename/pivot instances.
- `manage_properties` — get/set properties, attributes, tags.
- `manage_scripts` — create/read/write/edit/search script source.
- Playtest + logs — start/stop Play, inject test scripts, read output/errors.

**Weppy rules of engagement:**
- Tier is **Basic (free):** individual create/set/script calls work; bulk ops (`mass_create`, `create_tree`, etc.) are Pro — make individual calls instead.
- Prefer purpose-built actions over `execute_luau`; use arbitrary Luau only when no typed action fits.
- After any mutation, **verify** with a readback (`query_instances`), a preview/check, logs, or a playtest.
- Do **not** invent Roblox asset IDs — use user-provided IDs only.
- Do not capture Edit-mode screenshots while a playtest is active.
- Relevant skills: `weppy-roblox-mcp-guide` (actions/UI/playtest), `weppy-roblox-sync-guide` (Studio↔local sync).

Version control: Weppy Basic offers one-way Studio→Local sync; use it (or periodic `.rbxm` export) to feed Git when we want history.

## Architecture (server-authoritative; never trust the client)
Folder layout to create in Phase 1:
- `ServerScriptService/Server/` — all server scripts
- `StarterPlayerScripts/Client/` — all client scripts
- `ReplicatedStorage/Shared/` — shared modules + RemoteEvents
- `ReplicatedStorage/Assets/` — sounds, particles, UI templates
- `ServerStorage/Maps/` — submarine section models

**RemoteEvents** (`ReplicatedStorage/Shared`): `FloodUpdate`, `PowerUpdate`, `CreatureUpdate`, `PlayerDied`, `InteractRequest`, `InventoryUpdate`.

**Shared data ModuleScripts:** `SectionData` (flood rates/breaches/thresholds), `ItemData`, `EndingData`, `CreatureData` (speeds + sound radius per state).

**Server managers:** `FloodManager`, `OxygenManager`, `PowerManager`, `CreatureManager`, `InventoryManager`, `EndingManager`, `BatteryManager`.
**Client:** `CameraController` (first-person lock), `WaterRenderer`, `InventoryUI`, `AudioManager`.

**Stack:** Luau · RemoteEvents for all state sync · PathfindingService (creature) · DataStoreService (endings/saves) · MarketplaceService · Future lighting (Atmosphere/ColorCorrection/Bloom/DepthOfField) · TweenService (lights/water/doors) · positional Sound objects.

## Submarine layout (bow → stern; there-and-back arc)
1. **Forward Torpedo Room** — start. Ankle-deep. Journal #1, flashlight + 1st battery, 1 escape-pod component, escape-pod launch panel. Creature never starts here.
2. **Crew Berthing** — 1st hiding locker, journal #2, glow sticks. Floods after main power.
3. **Galley & Mess** — oxygen canister, journal #3, first big sound event.
4. **Officers/Captain's Quarters** — locked (needs keycard from sonar). Fuse here, journals #4 & #5, combo safe (lore).
5. **Control Room** (central hub) — large/exposed. Ballast panel (needs fuse), sonar console (partial power), 1 escape-pod component. All paths cross here.
6. **Sonar & Radio Rooms** — keycard in sonar; radio room locked until main power; SOS executed here; journal #6.
7. **Conning Tower** (above 5) — ladder up. Optional. Creature CANNOT climb → safe.
8. **Engine Room** — darkest/loudest. Main generator (restores main power → creature alerted). 1 escape-pod component. Floods rapidly once discovered.
9. **Aft Torpedo Room** — most dangerous, waist-deep from start. Creature patrols originate here. Secret exterior-hull passage (secret endings).

## Key systems + tuning constants
**Flooding** (`FloodManager`): per-section level 0–100; base rate from `SectionData`; fires `FloodUpdate` every 2s. Section 9 starts at 40; Section 8 escalates when discovered. Bulkhead doors seal to isolate flooding (permanent, cuts routes). Creature can't enter flooded rooms. Water muffles/distorts audio.
- Swimming state at level **40–80**: movement −40%, footsteps→water sounds, creature hearing reduced.
- Oxygen (`OxygenManager`): drains when player's section level **> 80**, over **30s**; canister +30s; hits 0 → **Drowned** ending.

**Power** (`PowerManager`): 3 independent circuits.
- *Emergency* (always on): dim red lighting; creature **Dormant**.
- *Main* (engine-room generator, 5s startup): brighter flickering lights, unlocks radio + sonar, starts generator hum, creature → **Alerted**. Major difficulty spike.
- *Ballast* (fuse from Captain's → ballast panel in §5): enables Surface-Manually ending; no creature effect.

**Creature** (`CreatureManager`, PathfindingService) — single NPC, never fully modeled/visible:
- **Dormant:** patrol §9↔§1, **8 studs/s**, sound radius **30**.
- **Alerted:** semi-random §5–9 (anchored to generator), **14 studs/s**, sound radius **60**.
- **Hunting:** pathfind to last sound, **22 studs/s**; searches 15s then reverts; reaching player → **Taken** ending.
- Cannot enter: flooded rooms (water > 60), conning tower, sealed sections.
- Sound intensities: walk=low, crouch=none, run=high, interact=medium, splash=high.
- Hiding: locker → player sound = 0; high mouse-delta fires `HeartbeatSound` (medium); creature lingers ~35s at locker then leaves. Player must physically hold still.
- Creature audio tiers by distance: far=rumble 0.1, mid=dragging 0.4, close=breathing 0.8; Hunting = 2s silence then charge at full volume.

**Inventory** (`InventoryManager`): **exactly 4 slots — do NOT increase (intentional pressure).**
- Flashlight: not a slot; `BatteryManager` charge 0–100, drains 1 per 8s, flickers < 20, dies at 0; battery item +50; submerged > 10s = extra drain.
- Key items (take a slot): Keycard (single-use), Fuse, Escape-Pod Component ×3 (§1/§5/§8). Carrying all 3 components = 3 of 4 slots.
- Journal pages: auto-collected, no slot.
- Consumables (take a slot): Battery, Glow Stick (place, 3-min light, non-retrievable), Oxygen Canister (+30s submerged).

**Endings** (`EndingManager`, 8 total; existence hidden from player):
- *Good:* **Escape Pod** (3 components + §1 panel) · **SOS** (main power + radio console + survive 8 real minutes) · **Surface Manually** (ballast power + valve-sequence puzzle).
- *Bad:* **Drowned** (oxygen 0) · **Taken** (creature reaches player) · **Sealed In** (all bulkheads sealed → oxygen depletes; punishes over-caution).
- *Secret:* **The Truth** (all 6 journals + return cargo at exterior hull → creature peaceful, then any good route) · **Hubris** (all 6 journals + take cargo + any good ending → dark post-credits).
- Persist discovered endings per player via DataStore.

## UI / visual constraints
Minimal HUD only: flashlight battery icon (bottom-left), oxygen bar (only when submerged), 4 inventory slots (bottom-center). **No** minimap, objective markers, or health bar (one creature hit = death). Future lighting; palette = deep navy / rusted orange / emergency red. First-person camera lock is essential — never allow third-person.

## Implementation phases (sequential; finish + test each before next)
1 Setup & architecture · 2 Build 9 sections (geometry) · 3 Flooding · 4 Power · 5 Creature AI · 6 Inventory & items · 7 Endings · 8 Audio (allocate full time) · 9 Polish & FX · 10 Monetization & DataStore · 11 Testing & balancing · 12 Launch.

Monetization is cosmetic/content-only (no pay-to-win): Supporter Pass, Extended Nightmare Mode, Developer Commentary; dev products (hints, extra save slot); cosmetic suit/flashlight/death-screen skins.

## Gotchas
- All state sync through RemoteEvents — server is authoritative.
- Do not fully model/reveal the creature; its power is sound + imagination.
- Test the flooding system constantly — it's the backbone.
- Build sections modularly (each should work as a standalone test environment).
