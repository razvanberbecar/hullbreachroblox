# Hull Breach — Project Guide

First-person atmospheric submarine **horror game** for Roblox (Luau). The player wakes as the sole survivor in a crashed, flooding submarine on the ocean floor. A blind, sound-hunting creature stalks the corridors. Explore 9 sections, restore power, manage a 4-slot inventory, piece together the captain's log, and reach one of **9 endings**. Solo by default; opt-in **2-player co-op**.

- **Name:** **Hull Breach** (formerly "Deep Descent"). Code identifiers still use the old name — see *Naming* below.
- **Genre:** Horror / Survival / Puzzle — **first-person only**, 13+
- **Status:** Code-complete and **published/live** (all 12 original phases + co-op, run randomization, leaderboards, monetization). Current work is polish, art, balancing and bug fixes.
- **Original design doc:** `C:\Users\Razvan\Desktop\DeepDescent_GameDesignDocument.docx` — historical. The code has diverged on purpose (tuning, extra ending, co-op); **trust the live code over the GDD**.

## Core design philosophy (do not violate)
- Atmosphere over jump scares — fear comes from *not knowing*.
- Every mechanic serves the narrative (flooding *is* the story, not just a timer).
- Player agency — multiple valid approaches to every problem.
- **Sound is 50% of the horror.**
- Respect the player — no hand-holding, environmental storytelling only.
- When unsure about a mechanic, ask: *does this add tension or frustration?* Only add tension.

## Where things live
- **Source of truth = the live Studio place:** "Hull Breach", **placeId `95779056096948`**, edited via **Team Create** (Razvan + David). Always check `system_info connection` → `actualPlaceId == 95779056096948` before mutating; Razvan also has an unrelated template place open sometimes.
- **GitHub:** https://github.com/razvanberbecar/hullbreachroblox (**public**). `src/` is a **one-way snapshot** of all 37 scripts, laid out by service (`.server.luau` = Script, `.client.luau` = LocalScript, `.luau` = ModuleScript). Editing `src/` does NOT change the game. To refresh: `get_source` every script via Weppy, then extract from Weppy's tool-history log (`weppy-project-sync/place_95779056096948_DeepDescent/observability/tools/history/*.jsonl`) and verify line counts.
- **Dev log:** append a dated entry to `DevLog/WORKLOG.md` every session (newest at top, never rewrite old entries; give script/instance paths and old → new values). `ServerStorage/DevLog/WORKLOG` inside the place is the older in-Studio log.
- `DiscordServer/` — discord.py bot for the community server (`post_announcement.py` posts to #announcements). Token lives in git-ignored `bot_token.txt`.

## Build workflow — Weppy MCP (NOT Rojo)
Built through **Weppy** (`weppy-roblox-mcp`), an MCP server that drives a **live Roblox Studio session**. Registered via `.mcp.json`; dashboard at http://localhost:3002. The Weppy server runs standalone in a PowerShell window — keep it open.

- **Tier varies:** it has been Pro, but was **Basic on 2026-10-11** (`execute_luau`, bulk ops and Pro query actions blocked). Check `system_info usage`; on Basic use individual typed calls.
- Tool groups: `query_instances` (read tree), `mutate_instances`, `manage_properties` (props/attrs/tags), `manage_scripts` (source), playtest + `manage_logs`. Action reference: `~/.claude/plugins/marketplaces/hope1026-roblox-mcp/plugins/weppy-roblox-mcp/skills/weppy-roblox-mcp-guide/references/mcp-actions.md`.
- Prefer typed actions over `execute_luau` (its sandbox also blocks `require`, HttpService and DataStoreService).
- **Verify every mutation** with a readback, logs or a playtest. Don't invent asset IDs. No Edit-mode screenshots during a playtest.
- Weppy sees the **Edit** DataModel: runtime-only things (`DD_*` dressing, the creature, menu scene) are invisible to queries — verify them in Play.
- **Team Create drops unsaved edits**, newly inserted scripts/instances most of all. Tell Razvan to **Ctrl+S right after changes** (and Publish to push live). Prefer editing existing scripts over adding new ModuleScripts.

## Architecture (server-authoritative; never trust the client)
- `ServerScriptService/Server/` — `Bootstrap` (single entry; starts managers in order) + `LightingSetup`, and the ModuleScript managers: `MapBuilder` → `InteractionManager` → `FloodManager` → `OxygenManager` → `PowerManager` → `CreatureManager` → `InventoryManager` → `BatteryManager` → `EndingManager` → `MatchmakingManager` → `PolishManager` → `DataManager` → `MonetizationManager`, plus `ItemModels` (item meshes, used by MapBuilder/drops). Each exposes `Start()`; most have `Reset()`/`ResetPlayer()` for run restarts. Managers reach each other lazily via a local `getManager(name)` (pcall-require).
- `StarterPlayer/StarterPlayerScripts/Client/` — `CameraController` (first-person lock + suit skins), `FlashlightController`, `HUD` (oxygen, notify line, journal reader, hint button), `InventoryUI`, `WaterRenderer`, `SoundProducer` (movement speed + sounds the creature hears), `AudioManager` (full mixer), `EndingClient` (cutscenes, ballast keypad, SOS timer, commentary panel), `MenuUI` (menu, store, settings, co-op UI), `Reticle`. `ReplicatedFirst/IntroScreen` = join cover + story prologue.
- `ReplicatedStorage/Shared/` — data modules `SectionData`, `ItemData`, `CreatureData`, `EndingData`, `GameConfig` (cross-cutting tunables), `SoundData`, `MonetizationData`, and **`Net`**.
- **Networking:** every RemoteEvent/RemoteFunction is declared in `Shared/Net` (`Net.Events` / `Net.Functions`, ~44 remotes) and accessed via `Net.Event(name)` / `Net.Func(name)`; the server creates them in `Net.Init()`. Add new remotes there. Client→server handlers must validate types and state. (`SealDoor` is declared but deliberately unhandled: sealing goes through the proximity-validated prompt, so clients can't seal doors remotely.)
- **Map:** the sub is **baked** into `Workspace.Submarine` (attribute `Baked=true`), so `MapBuilder.Build()` reuses it; delete the folder or clear `Baked` to regenerate procedurally. `MapBuilder.Dress()` **destroys and rebuilds every `DD_*` instance** at each server start (props, dressing, Supporters wall) — change dressing in `MapBuilder`, never by hand-editing `DD_*` parts. Mesh prop templates live in `ServerStorage.DeskProps`. `BuildMenuScene()` builds the menu backdrop.
- **CollectionService tags** drive systems generically: `WaterPlane`, `EmergencyLight`, `MainLight`, `BulkheadDoor` (attrs SectionA/SectionB/Open/Sealed), `Interactable` (attr `Kind`), `Pickup` (attr `ItemId`), `Journal` (attr `PageIndex`), `HidingSpot`, `HullBreach`, `SurvivorsWall`. All ProximityPrompts route through `InteractionManager`; systems add behaviour with `InteractionManager.Register(kind, fn)`.
- **Naming:** player-facing text and log prefixes say Hull Breach (`[HullBreach]`), but DataStore keys (`DeepDescent_PlayerData_v2`, `DD_*`), GUI names (`DeepDescent*`), attributes (`DD_*`) and `_G.DeepDescent` keep the old name. **Never rename DataStore keys** — it wipes every player's saves.

## Submarine layout (bow → stern; there-and-back arc)
Sections sit along +X, 56 studs apart, in hull order 1-2-3-4-5-6-8-9. Interior 48 × 24 × 16 studs, floor at y=0. §7 sits above §5. Start water level in brackets (0–100).
1. **Forward Torpedo Room** [12] — spawn. Flashlight (fixed), battery, pod component #1, journal 1, escape-pod launch panel, broken-panel hiding spot, Supporters wall. Creature never starts here.
2. **Crew Berthing** [4] — two hiding lockers, glow stick, journal 2. Barely floods until main power comes on.
3. **Galley & Mess** [6] — oxygen canister, journal 3 (notice board). Scripted structural groan on first entry.
4. **Officers/Captain's Quarters** [5] — captain door needs the keycard (single use). Fuse, journals 4 + 5, vault safe (lore).
5. **Control Room** (hub) [8] — ballast panel (fuse → valve puzzle), pod component #2, ladder to §7.
6. **Sonar & Radio** [7] — keycard, journal 6, sonar console (works on emergency power; reports creature distance/bearing), radio console (SOS; needs main power).
7. **Conning Tower** [0] — optional refuge; creature cannot enter. Periscope, scripted sighting.
8. **Engine Room** [6] — generator (main power), pod component #3, battery. Floods fast (0.5/s) once discovered.
9. **Aft Torpedo Room** [40] — waist-deep, oxygen canister, creature origin. Hull breach (→ *The Deep*) and the sealed cargo crate at the exterior passage (secret endings).

## Key systems + tuning (values live in the Shared data modules)
- **Flooding** (`FloodManager`, `GameConfig`, `SectionData`): per-section level 0–100, global +0.02/s plus each section's rate (0.03–0.10/s), 0.5s tick, `FloodUpdate` every 2s. Water **equalizes through open bulkhead doors**. Sealing a door is permanent. Everything (flood, oxygen, creature) idles while every player is still in the menu (`InMenu` attribute).
- **Swimming / oxygen** (`OxygenManager`): swimming at level 40–80 → speed ×0.6, splash/swim sounds. Oxygen drains when the player's **head is below the water line** (crouching dips it 1.8 studs). 30s max, regenerates 6/s, canister +30s. Sealed in with every adjacent door sealed → slow suffocation (0.35×) → *Sealed In*.
- **Movement & sound** (`SoundProducer`, `CreatureData.SoundIntensity`): walk 14 / crouch 7 (Ctrl or C, silent) / run 22 (Shift). Intensities: crouch 0, walk 1, interact 2, swim 2, heartbeat 2, run 3, splash 3. Door toggles are heard by the creature.
- **Power** (`PowerManager`): *Emergency* — always on, flickering red. *Main* — engine-room generator, 5s start-up: work lights + room glow, radio unlocks, generator hum, crew berthing starts flooding, **creature → Alerted**. *Ballast* — install the fuse at the §5 panel → opens the valve puzzle (re-openable).
- **Creature** (`CreatureManager`, `CreatureData`) — section-waypoint movement (**not** PathfindingService). A dark, semi-transparent anglerfish-like silhouette; its only glow is the lure.
  - Dormant: patrols the hull, speed 8, hears within 40 studs or 1 section.
  - Alerted: roams §5–9, pulled toward the generator (§8), speed 18, hears within 95 studs or 3 sections.
  - Hunting: goes to the last sound at speed 24, searches 15s (10s if someone is hiding nearby), then reverts. Kill radius 5 → *Taken*.
  - Catches anyone who moves within 5 studs, even crouched. Water muffles sound (down to ×0.55 at full flood). Won't enter sections with water ≥ 60, the tower, or sealed doors.
  - **Adaptive:** remembers which lockers you use most and comes back to check them.
  - Hiding: in a locker the player's sounds are ignored except heartbeat, which fires from high mouse movement. Exit with E via the `ExitHide` remote.
  - Creature audio (client): distant rumble → wet drag → breathing as it gets closer; on entering Hunting: startle screech, 2s silence, then the charge.
- **Inventory** (`InventoryManager`, `ItemData`): **exactly 4 slots — never increase.** Keys 1–4 select, E use, Q / right-click drop (spawns a re-collectable pickup). Key items: keycard, fuse, pod component ×3. Consumables: battery (+50), glow stick (placed, lights 3 min, can't be picked back up), oxygen canister (+30s). Journal pages are auto-collected, stay in the world and can be re-read.
- **Flashlight** (`BatteryManager` + `FlashlightController`): its own slot (not one of the 4), F toggles. 0–100 charge, drains 1 per 8s only while on, extra drain after 10s submerged, flickers below 20.
- **Endings** (`EndingManager`, `EndingData`) — 9 total; existence hidden from the player:
  - Good: **Escape Pod** (3 components + the §1 panel) · **SOS** (main power + radio, then survive **2 minutes**) · **Surface Manually** (fuse + valve sequence).
  - Bad: **Drowned** · **Taken** · **Sealed In** · **The Deep** (swim out through the §9 breach).
  - Secret: **The Truth** (all 6 pages + return the cargo → creature peaceful) · **Hubris** (all 6 pages + take the cargo + any good ending).
  - After an ending, Try Again / Main Menu does a full world reset (snapshot restore). The Reset Character button is rerouted to the same full restart.
- **Run randomization** (`EndingManager.randomizeRun`, every run): shuffles positions of non-fixed pickups (flashlight, keycard and fuse stay put) and of the journals; random creature start (§3/4/5/6/8/9); per-section flood-rate ×0.6–2.5 (§1 capped at ×1); random 5-valve ballast order, with clues appended to journal pages 1–5.
- **Co-op** (`MatchmakingManager`, `EndingManager`): one place. The **public server is a router menu** (Play Solo / Play With a Friend → Invite or Quick Match); gameplay runs in **reserved servers**. The run starts only when every present player has pressed Play. Shared fate (any death ends it for both), shared win, key items pooled across inventories. A co-op host plays alone if no partner arrives within 35s. Server kind is exposed to clients via `ReplicatedStorage` attribute `DD_ServerKind`.
- **Menu / meta** (`MenuUI`, `DataManager`): main menu (Play, Endings Log, Store, Leaderboards, Settings, Credits; skip-intro checkbox). In a run: [L] records/store overlay, [H] hint, [M] pause → Return to Lobby (reserved servers only). Saves: account-wide meta (passes, cosmetics, settings, records) + up to 3 save slots of ending progress. If a load fails, the session runs read-only to protect saved data. Leaderboards (OrderedDataStores): most endings, longest survival, fastest escape per winning ending (the 3 good ones + the 2 secret ones).
- **Audio** (`SoundData`, `AudioManager`): all IDs are filled with free Creator Store sounds; `SoundData.Make` / `HasAsset` guard any missing ones. Layers: hull groan, water rush (scales with local flood), breathing windows, heartbeat while hiding, positional `SoundCue` one-shots.
- **Lighting** (`LightingSetup`): LightingStyle Realistic, deep-navy ambient, fog, Atmosphere, ColorCorrection, Bloom, DepthOfField. Hull walls/ceilings use the **MG-Rust 30** MaterialVariant; floors are CorrodedMetal.
- **Test aids** (`GameConfig`): `FreezeCreature` (creature spawns but never moves or kills), `Debug` (verbose prints) — both must be `false` for release.

## UI / visual constraints
Minimal HUD only: 4 inventory slots + the flashlight slot with a battery bar (bottom-center), oxygen bar only while in danger, a one-line notification, a small Hint button (top-right) and a center-dot reticle. **No** minimap, objective markers or health bar (one creature catch = death). Palette: deep navy / rusted orange / emergency red. **First-person lock is essential — never allow third-person.**

Monetization is cosmetic/content-only (no pay-to-win): game passes Supporter (Supporters wall), Extended Nightmare Mode (harder; only after completing the game) and Developer Commentary; dev products Hint and Extra Save Slot; cosmetic flashlight beams, suits and death animation. Real IDs are set in `MonetizationData`; `DiscordInvite` is still blank.

## Gotchas
- **Keep `Workspace.StreamingEnabled = false`** — with streaming on, MaterialVariant walls pop from plain metal to rust as you walk.
- **Flashlight `SpotLight.Shadows` must stay false** (a camera light self-shadows on the player's body under Realistic lighting). The light stays Enabled; only Brightness toggles it, to avoid a first-use lighting hitch.
- A ProximityPrompt won't reliably re-trigger from inside its own part — exit hiding via the `ExitHide` remote, not the prompt.
- `Workspace.Baseplate` sits at y=-12 on purpose (at y=0 it z-fought the sub floor).
- **Studio can't test:** TeleportService / MemoryStore (co-op), DataStores (saves, leaderboards), and `HttpService:GetSecret` all only work on a **published server**. The experience must be **Public** for friend invites. Client-side `game.PrivateServerId` is unreliable — use `DD_ServerKind`.
- **Secrets:** the Developer Commentary Discord webhook is the Roblox Secret `dev_rating_webhook` (server-only). Never put URLs/keys in `Shared/*` (replicates to clients) or in the repo — GitHub is public. `.claude/settings.local.json`, `DiscordServer/bot_token.txt` and `weppy-project-sync/` are git-ignored; scan staged changes before every push.
- The MG-Rust texture asset is owned by another creator. It renders in Play, but worth one check on a live server for non-developer players.
- Test the flooding system after any change touching sections, doors or water — it's the backbone.
