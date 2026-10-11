# Deep Descent — Work Log

Newest entries at top. Append a dated entry every working session; never overwrite older ones.
Be factual — give script/instance paths, and for tuning changes give old → new values.

> Note: this file was recreated on 2026-07-01 because the `DevLog/` folder was missing on
> this machine. If an older `WORKLOG.md` exists elsewhere, merge these entries back into it.

---

## 2026-10-11 — Claude (Razvan session) [GitHub repo + script export + CLAUDE.md rewrite]

**No changes to the Studio place this session** (read-only: script sources, `Workspace.Submarine`
attrs, `Workspace.StreamingEnabled`, `Players.MaxPlayers`).

- **GitHub:** the project folder is now a git repo pushed to
  https://github.com/razvanberbecar/hullbreachroblox (branch `main`, **public**). New root `.gitignore`
  keeps out `DiscordServer/bot_token.txt`, `.claude/settings.local.json` (contains a live Discord
  webhook URL), `weppy-project-sync/` (71 MB of Weppy logs) and `__pycache__`.
- **`src/`:** read-only snapshot of all **37 scripts** from the Hull Breach place, by service
  (`.server.luau` = Script, `.client.luau` = LocalScript, `.luau` = ModuleScript). Line counts verified
  against Studio; secret-scanned before push (none found — the commentary webhook is a Roblox Secret).
  It is a snapshot, not a sync: Studio stays the source of truth; ask Claude to re-export after changes.
- **`CLAUDE.md` rewritten** to match the live game (it still said "pre-Phase 1"): name Hull Breach,
  real tuning values, 9 endings, co-op, run randomization, `Net` remotes, baked map + `Dress()`, gotchas.
- Weppy reported **Basic** tier today (`execute_luau` blocked) — previously Pro.

Verified live: `Workspace.Submarine` `Baked=true`, `StreamingEnabled=false`, `MaxPlayers=60`.

---

## 2026-07-06 — Claude (Razvan session) [Floor z-fighting fix (water vs floor)]

**Razvan reported the floor "glitchy — like 2 textures fighting when the camera moves."** Diagnosed as
z-fighting between the client water volume and the floor, NOT a material/decal issue.
- The baked floors are plain DiamondPlate, top surface at world **y=0**, no decals/variant (verified
  Section_5 Floor: pos y=-1, size.Y=2 → top y=0; 0 children). One Floor per section, no duplicate geometry.
- `WaterRenderer` grew each section's water volume from `SectionData.FLOOR_Y` (**=0**) upward, so the water
  box's **bottom face sat exactly on the floor's top face** (both y=0). Two coincident surfaces → z-fight.
  Only visible in Play (client-rendered water) and in sections with water — e.g. Section 1, which spawns you
  ankle-deep, so it showed immediately.
- Fix (`Client/WaterRenderer.renderSection`): sink the volume bottom `BOTTOM_SINK = 0.6` **below** the floor
  (`bottomY = FLOOR_Y - 0.6`), so the bottom face is buried inside the opaque floor part (y=-2..0) instead of
  coinciding with the floor top. Water still visually fills from the floor up; the buried strip is occluded.
  Submerged detection unchanged (still uses `LevelToWaterY`).
- Verified: `run_test` with the flood forced on for ~5s → `renderSection` ran, **0 WaterRenderer errors**
  (only the usual DataStore-in-Studio noise). This is Studio-testable (local-play) — F5 → PLAY → look at the
  Section 1 floor. NEEDS CTRL+S + Publish.

**FOLLOW-UP — the water sink didn't fix it; the real cause was the floor MATERIAL.** Razvan retested: floor
looked "exactly the same." So the "two textures" was the **DiamondPlate** material itself moiré/shimmering
under camera motion (its fine diamond pattern aliases badly), not the water z-fight. Confirmed the floors are
a single DiamondPlate part each (no overlay: `MapBuilder.box("Floor"...)`, no runtime re-apply — line 1192
is just `placeJournals()` raycasting; map is baked so nothing re-sets material at runtime). Fix: Razvan chose
**CorrodedMetal**; set `Material=CorrodedMetal` + `Reflectance=0` on all **16** floor parts (8 section Floors +
TowerFloor + 7 CorrFloors) via `mass_set` (16/16 ok). Matte rust reads well for a flooded wreck and doesn't
shimmer. The water-bottom sink (BOTTOM_SINK 0.6) is kept — harmless and still removes the coincident-face case.
**Baked property edits → CTRL+S NOW** (baked-edits-can-revert) + Publish. Studio-testable: F5 → PLAY → §1 floor.

**ACTUAL ROOT CAUSE (found on the 3rd report) — the default `Workspace.Baseplate`.** Razvan: floor "flickers
transparent and I can see the squared Studio floor." That's the **Baseplate** showing through. Its top face
was at **y=0** (Position y=-8, Size.Y=16 → top 0) — the SAME plane as the sub floor top (y=0) → classic
two-opaque-surface z-fight; when the baseplate won a pixel you saw its grid through the floor. Neither the
water nor the material could fix this (it's a second part). Fix: lowered the Baseplate to **Position y=-12**
(top face now -4, i.e. 2 studs below the sub floor underside at -2) via `execute_luau` (the typed set choked
on Vector3/CFrame values — "got string"). `Workspace.SpawnLocation` checked + cleared (Transparency 1, top at
y=1, not a factor). CorrodedMetal floors + the water sink are kept (both fine). **CTRL+S + Publish**, then
F5 → the §1 floor should be rock-steady. NOTE: if regenerated procedurally, MapBuilder should also lower/skip
the baseplate — but map is baked, so the y=-12 edit is what ships.

---

## 2026-07-06 — Claude (Razvan session) [Co-op: Return to Lobby]

**Added a way to get back to the Solo/Co-op chooser from a gameplay server without leaving + rejoining.**
Previously, once teleported into a solo/co-op reserved server, the only way back to the front-door menu was
to leave the game and re-enter.

- **`Shared/Net`**: +`RequestLobby` (C2S).
- **`Server/MatchmakingManager`**: `RequestLobby` handler (wired in `Start()`, works on any server type) →
  `TeleportAsync(PLACE_ID, {player})` with **no** ReservedServerAccessCode + no teleport data → lands them on a
  normal PUBLIC router server showing the Solo/Co-op menu. Notify on teleport failure.
- **`Client/MenuUI`**:
  - `returnToLobby()` fires `RequestLobby` (Roblox's teleport screen covers the transition).
  - **"LEAVE TO LOBBY"** button added to the reserved server's menu (post-run menu, `isReserved` only).
  - **In-game pause menu** (own `DeepDescentPause` ScreenGui, DisplayOrder 70): press **M** during a run to open
    PAUSED → RESUME / RETURN TO LOBBY (with an "ends your current dive" warning). Frees the cursor while open via
    the ballast-puzzle pattern (BindToRenderStep MouseBehavior.Default + UIModalOpen), won't open over the ballast
    puzzle. Reserved servers only (Studio/public have no lobby to teleport to).
  - Tightened `detectReserved()` to treat only `mode == "solo"/"coop"` as a gameplay server, so the no-mode lobby
    teleport correctly resolves to the public router menu.
- Co-op partner handling: if one co-op player returns to lobby mid-run, the existing reserved partner-leave logic
  drops the requirement so the remaining player continues (solo-fallback). Verified: `run_test` boot clean,
  RequestLobby remote present, no errors. Studio can't exercise the teleport (public server) — **live test the M
  menu + Leave to Lobby button after publishing.** NEEDS CTRL+S + Publish.

---

## 2026-07-05 — Claude (Razvan session) [2-player co-op — Half 2: join / matchmaking layer]

**Built the opt-in join layer: solo & co-op both run in private (reserved) servers on ONE place.
This half only works on a PUBLISHED server (TeleportService/MemoryStore are dead in Studio), so it's
publish-and-test-live. Server boot verified clean in Studio (all external calls pcall-guarded / no-op).**

Architecture: single experience, single place, distinguished at runtime by server type.
- PUBLIC server (`game.PrivateServerId==""`) = front-door "router": shows the menu; nobody plays here.
- RESERVED server (`PrivateServerId~="" and PrivateServerOwnerId==0`) = the actual game, reached only by
  teleport. Solo = reserved w/ 1; co-op = reserved w/ 2 (`EndingManager.SetExpectedPlayers(2)`).
- STUDIO is a public server but can't teleport, so the client treats Studio (and reserved servers) as
  "play locally" — the game stays fully testable in Studio via a single PLAY button + the Half-1 ready-gate.

Changes (live place `95779056096948`):
- **`Shared/Net`**: +5 remotes — `MatchmakingStatus` (S2C) and `RequestSolo`/`RequestCoopHost`/
  `RequestQuickMatch`/`CancelMatchmaking` (C2S).
- **`Server/MatchmakingManager`** (NEW, ~252 lines; added to `Bootstrap` MANAGER_ORDER after EndingManager):
  - Reserved server: reads each arrival's `GetJoinData().TeleportData`; co-op → `SetExpectedPlayers(2)` +
    (host) fires `inviteReady` so the client prompts the Roblox invite; **solo-fallback** — if still alone
    after 35s (friend never joined / partner left), `SetExpectedPlayers(1)` + `EndingManager.TryStart()` so
    nobody is ever stuck. Also drops the requirement if a co-op partner leaves.
  - Public router: `RequestSolo` (ReserveServer + TeleportAsync {mode=solo}); `RequestCoopHost` (reserve +
    stash `joinKey→accessCode` in a MemoryStore SortedMap + teleport host {mode=coop,host,joinKey});
    `RequestQuickMatch`/`CancelMatchmaking` (MemoryStore **queue** + a matcher loop that pairs 2 & reserves a
    server, and a poll loop that teleports each local searcher once assigned); invited-friend `LaunchData`
    arrivals → look up accessCode → teleport into the reserved server. All Teleport/MemoryStore pcall-guarded;
    matcher/poll loops skipped under `RunService:IsStudio()`.
- **`Server/EndingManager`**: +`EndingManager.TryStart()` (re-checks the ready-gate after the expected-player
  count changes — used by the solo-fallback / partner-leave paths).
- **`Client/MenuUI`**: server-type branch. Router shows **PLAY SOLO** (→RequestSolo) + **PLAY WITH A FRIEND**
  (→ co-op panel: Invite a Friend →RequestCoopHost, Quick Match →RequestQuickMatch/Cancel). Reserved/Studio
  shows a single **PLAY** (local ready-gate). Reserved servers auto-run the ready-gate on arrival (skip the
  menu; intro plays after RunStarted) with an "Invite a Friend" button on the wait overlay. `MatchmakingStatus`
  drives a connecting overlay (solo/invited) or the co-op panel status (searching/found/error).
  `SocialService:PromptGameInvite` sends the invite with the joinKey as LaunchData.

Verified: `run_test` server boot PASSED — MatchmakingManager requires + Start present, Bootstrap starts it,
detects Studio as public router, all 5 remotes present, EndingManager.TryStart present, MenuUI init runs with
0 client errors (only the pre-existing DataStore Studio-access errors). NO Studio verification of teleport/
matchmaking is possible.

**LIVE TEST PLAN (Razvan, on a PUBLISHED server):**
1. Publish. In Creator Hub set **Server Size / Max Players = 2**.
2. Solo: join → PLAY SOLO → should teleport into a private server, alone, game plays as before.
3. Invite: join → PLAY WITH A FRIEND → Invite a Friend → teleported to a private co-op server + Roblox invite
   prompt. Second account accepts → lands in the SAME server → both ready → shared run. (If friend never joins,
   solo-fallback starts you alone after ~35s.)
4. Quick match: two accounts, both PLAY WITH A FRIEND → Quick Match → should pair into one private server.
5. Confirm a stranger can NEVER join a solo game (all gameplay is in reserved servers).

**NEEDS CTRL+S + Publish.** Known edge for later: dedupe a player double-queuing quick-match; richer status UI.
Half 2 files: Net, MatchmakingManager (new), Bootstrap, EndingManager, MenuUI.

**BUGFIX (same session, from Razvan's first live test):** Play Solo teleported to a new server but that
server showed the ROUTER menu again → clicking Play Solo re-teleported = infinite loop. Cause: the client
detected server type via `game.PrivateServerId`, which is **unreliable on the client** (reads empty in a
reserved server → `isReserved=false` → router menu). Fix: (a) `MatchmakingManager.Start()` now sets
`ReplicatedStorage:SetAttribute("DD_ServerKind", "reserved"/"public")` (server-side PrivateServerId IS
reliable); (b) `MenuUI` now detects via `TeleportService:GetLocalPlayerTeleportData()` (the mode we arrived
with — instant + reliable for reserved servers), falling back to the DD_ServerKind flag (waits ≤3s) for
fresh public joins. Verified in Studio: DD_ServerKind='public', no errors, Studio still shows local PLAY.
Re-publish to push the fix.

**BUGFIX #2 (same session, next live test):** after the loop fix, Play Solo teleported in but showed a
**stuck fully-black screen** (first-person, cursor locked). Cause: `ReplicatedFirst/IntroScreen` holds an
opaque black join-cover until the client-local attribute `DD_MenuReady` is set — and that's only set by
MenuUI's `enterMenu()`. The reserved-server auto-start **skips the menu**, so DD_MenuReady never got set and
the intro hung on black (20s timeout). Fix: `autoStartReserved()` now sets `DD_MenuReady=true` so the intro
fades in and the prologue plays normally when the run begins. Verified: MenuUI compiles, no errors. Re-publish.

**NON-CODE ISSUE #3 (invite):** friend got Roblox **error 524 "no permission to join this experience."** Cause:
the **experience was Private** (only owner/team can join) — solo worked for Razvan because he owns it. Fix:
set the experience to **Public** in Creator Hub. Not a code change. (Reserved-server invites require a Public
experience.) After that, **co-op works end-to-end — Razvan confirmed solo + Invite a Friend both work live.** ✅

**Announced:** posted a "2-Player Co-op is Live" embed to Discord **#announcements** (pinged @Announcements)
via a new `DiscordServer/post_announcement.py` (reuses the bot token; idempotent). Co-op is shipped.

---

## 2026-07-05 — Claude (Razvan session) [2-player co-op — Half 1: in-run mechanics]

**Started opt-in 2-player co-op. This session = "Half 1" (the in-run shared mechanics,
fully Studio-testable). The join/matchmaking layer is "Half 2" (publish-only, not started).**

Design locked with Razvan (via decision prompts):
- **Opt-in:** solo stays the default; co-op will be a menu button (Half 2).
- **Architecture:** ONE experience, ONE place, private/reserved servers (no strangers). No new
  experience/place needed. (Live place already reports `Players.MaxPlayers=60`; Half 2 sets it to 2.)
- **Shared fate:** any death ends the run for BOTH players. **Shared win:** any good ending wins for
  both; escape-pod counts components pooled across the crew. **Start when both ready.**
- **Join (Half 2, not built):** Invite a friend (TeleportService reserve + SocialService invite) AND
  Quick match (MemoryStore queue). `TeleportService` is dead in Studio → Half 2 is publish-and-test-live.

Key finding: the codebase was already ~70% co-op-ready — CreatureManager already targets the *nearest*
player and keeps per-player hiding/catch/kill; Oxygen/Inventory/Battery/Endings/Data are per-player;
Flood (`anyActive`, line ~129) + Oxygen (per-player `InMenu`, line ~83) + Creature already idle while
`InMenu=true`. The only real conflict was the run/world lifecycle (per-player triggers acting on a
shared world). Fixed by making the run a single shared lifecycle.

Changes (all in the live place `95779056096948`):
- **`Shared/Net`**: +3 remotes — `RunStarted` (S2C), `RunReset` (S2C, `{toMenu}`), `CancelReady` (C2S).
- **`Server/EndingManager`** (rewritten, 492→~600 lines):
  - `Trigger()` now ends the run for EVERYONE at once — `runEnded` guard (first trigger wins),
    `EndingTrigger`/`SurvivalUpdate` fired to ALL clients, ending + run-result recorded for every player.
  - **Ready-gate:** `StartRun` marks a player ready; `beginRun()` flips `InMenu=false` for the whole
    crew + broadcasts `RunStarted` only once `allReady()` (all present players ready; `expectedPlayers`
    hook, default = present count, so solo starts instantly). `CancelReady` un-readies.
  - **`ResetRun(triggerPlayer, returnToMenu)`** is now ONE global debounced reset (`lastGlobalReset`,
    init `-math.huge`) that rebuilds the shared world + resets EVERY player + broadcasts `RunReset`.
    `returnToMenu=true` → all to menu; false (Try Again) → fresh run for all immediately.
  - **Shared objectives:** `combinedItemCount("pod_component")` (escape pod ≥3 pooled) + `combinedJournalCount()`
    (Truth/Hubris 6-page gate pooled); hubris via `anyCargoTaken()`. SOS is one shared thread → `FireAllClients`.
  - Added `EndingManager.SetExpectedPlayers(n)` (Half-2 hook: co-op server sets 2 to wait for the partner).
- **`Client/MenuUI`**: `play()` now readies up + shows a "Waiting for your partner…" lobby overlay
  (Active frame, blocks menu; 0.4s delayed reveal so solo never flashes it) and defers the intro/gameplay
  release to a `RunStarted` listener (`beginGameplay()`); Cancel fires `CancelReady`.
- **`Client/EndingClient`**: +`RunReset` listener that fades out the ending screen for the player who did
  NOT click Try Again/Main Menu (guarded by `restarting`/`goingMenu` so the clicker's own fade still runs).

Verified: `run_test` (server boot) PASSED, 0 script errors. New remotes present; EndingManager requires
clean + full API; player boots `InMenu=true` (ready-gate holds the world inert); `ResetRun(nil,false)`
runs with no error and respawned 22 pickups + 12 journals (shared world rebuild OK); `SetExpectedPlayers`
callable. The only log errors were `StudioAccessToApisNotAllowed` (DataStore, Studio-only, pre-existing).

**NOT yet verified (needs a real 2-client test):** the actual both-ready gate, shared death screen on
both clients, and single-reset syncing both — automated `run_test` can't click Play. **Razvan: test via
Studio → Test tab → Clients and Servers → 2 players → Start.** Expected: run stays in menu until BOTH
press Play; one death → both see the death screen; either player's Try Again → both resume one fresh run.

**NEEDS CTRL+S + Publish** — 4 script edits (Net, EndingManager, MenuUI, EndingClient) in the live
Team Create place. Half 2 (menu Co-op button + reserved-server invite/quick-match + MaxPlayers=2) is next.

---

## 2026-07-04 — Claude (Razvan session) [Hull rust textures + spawn-decal fix]

**Applied a rust PBR MaterialVariant to every hull wall, and fixed a stray spawn.**

Context: a prior (07-03, unlogged) session imported a 32-variant rust texture pack into
`MaterialService` (`MG-Rust 01`…`MG-Rust 32`, all `BaseMaterial = Metal`) and built a preview
grid `Workspace._SwatchBoard` (32 lit 10x10 tiles, labels 01–32, 3 SwatchLights) floating at
y≈112 so Razvan could pick one. The hull walls were still on the defunct AI variant
`deepdescent_hull_rust` (`Material = CorrodedMetal`), which silently fell back to plain metal —
i.e. flat, "no texture" look.

- Razvan picked the **peeling-painted-steel** family, hero tile **MG-Rust 30** (blue paint flaking
  off orange rust — reads well under the dim red emergency light).
- Applied `Material = Enum.Material.Metal` + `MaterialVariant = "MG-Rust 30"` to **81 hull parts**:
  Section 1's 6 walls (WallZpos/WallZneg/EndWall/EndWallL/EndWallR/EndWallTop) set individually,
  then a single `execute_luau` pass swapped the remaining **75** parts still on
  `deepdescent_hull_rust` across Sections 2–9, the conning tower (TowerWall A–D), all Connector
  corridors (CorrWallZpos/Zneg), and the Captain's sub-room walls. Leftover count verified 0.
  Ceilings and floors use different variants and were intentionally left alone (Razvan chose
  walls-only). The engine-room **`Generator`** was also on `deepdescent_hull_rust`, so it got rust
  too — kept it (thematically fine on an old generator); one call reverts it if unwanted.
- Spawn-decal bug: there were TWO enabled SpawnLocations in Section 1 — the intended
  `Workspace.Submarine.StartSpawn` (invisible, no decal, (8,1,-7)) AND a stray default
  `Workspace.SpawnLocation` at world origin (opaque, CanCollide, Roblox's spiky sunburst Decal),
  so players could spawn on the wrong one. Neutralized the stray (did not delete — I didn't create
  it): `Enabled` true→false, `Transparency` 0→1, `CanCollide` true→false, and its `Decal.Transparency`
  0→1. No game script references either spawn by name (grep of synced source = only tool-history hits).

Verified via Edit-mode screenshots: Section 1 walls show detailed corrosion (no stretch/tiling
artifacts at 48-stud wall scale), Section 1 floor is clean (sunburst gone), Section 5 control-room
walls carry the rust. `execute_luau` returned changed=75, leftover=0.

**Follow-up (same session, at Razvan's request):**
- Deleted `Workspace._SwatchBoard` (the 32-tile preview grid) now that MG-Rust 30 is chosen.
- Rusted all **8 ceilings** (`Section_*.Ceiling`) — they were plain `Material=Metal`, empty variant
  (flat, "plastic"-looking); now `Material=Metal` + `MaterialVariant="MG-Rust 30"`.
- Rusted Section 9's stern back wall: `SternCapL` + `SternCapTop` (both were flat plain Metal).
  Left `HullBreach` alone — it's the actual hole (semi-transparent `Glass`, Transparency 0.25), and
  `ExteriorPassage` (WoodPlanks secret hatch) untouched.
- Floors still built-in grating (DiamondPlate) — only remaining un-rusted hull surface, by design.

**NEEDS CTRL+S / republish** — all of the above are baked property edits on baked parts + a
MaterialService change; Team Create can drop unsaved baked edits (see the baked-edits-can-revert note).

**Z-fighting fixes (same session):**
- Doors/connectors: Razvan reported flicker at the corridor doors and proposed deleting each
  connector's `CorrCeil`/`CorrFloor`/`CorrWallZneg`/`CorrWallZpos`. Investigated geometry first —
  **deletion would punch holes**: every connector spans an 8-stud gap between two sections
  (e.g. Section1 floor ends x=24, Section2 starts x=32) and the Corr pieces are the ONLY floor/
  ceiling/side surfaces there. Real cause = the Corr walls/ceiling are built 8 studs long and
  interpenetrate each section's 2-stud-thick EndWall frame at both ends (coplanar faces → z-fight).
  Fix: `execute_luau` shrank `CorrWallZpos`/`CorrWallZneg`/`CorrCeil` on all 7 connectors from
  size.X=8 → 4 (symmetric, keeps center) so they occupy only the middle 4 studs; the EndWall frames
  already cover the trimmed 2-stud ends, so no holes (verified by screenshot at the §1 door — solid
  frame, closed bulkhead door visible, no void). `CorrFloor` left full-length (it bridges the gap).
  21 parts trimmed (3 × 7 connectors).
- Floors: reported "tiles glitch when camera moves." Not a z-fight (no coplanar floor partner in a
  room; CorrFloor abuts, doesn't overlap). Cause = DiamondPlate normal/specular shimmer (aliasing),
  mildly amplified by `Reflectance=0.04`. First pass: set `Reflectance=0` on all 15 floors
  (8 section Floors + 7 CorrFloors). If shimmer persists in motion, next step is swapping the floor
  material to a less busy one (plain Metal or a rust variant) — PENDING Razvan's in-motion check
  (can't be verified from static screenshots).

**Texture pop-in fix:** Razvan then reported the door/corridor textures "disappear after I start
walking." Diagnosed: `Workspace.StreamingEnabled = true`. With streaming on, parts near the streaming
edge stream in/out as the player moves, and a custom **MaterialVariant applies a moment AFTER its part
loads** — so the rust (MG-Rust 30, 91 parts) briefly shows base Metal then pops in, repeatedly while
walking. Was latent before because the old dead variant always showed base material anyway; applying a
real variant exposed it. The trim did NOT cause it (parts verified intact: Metal + MG-Rust 30).
Fix: **set `StreamingEnabled = false`** — appropriate for a small single-location level; whole sub
now loads once and stays resident, no pop. Reversible if ever needed (but keep OFF, see gotcha memory).
PENDING Razvan's in-motion confirmation.

**BIG FINDING — MG-Rust textures don't render at runtime (Studio-only):** After the streaming fix,
Razvan reported doors "look plastic in Play, fine in Studio edit." Diagnosed via `run_test` playtest
(props intact at runtime: walls = Metal + MG-Rust 30, variant present in MaterialService — NO script
override) + `manage_assets info` on the variant's ColorMap `rbxassetid://15564360320`: it's an Image
owned by **another user** (`RIP_Reset32176482`, id 2033401114), private, not-for-sale. Roblox enforces
ownership on MaterialVariant/PBR textures at RUNTIME → they render in Studio edit for the dev but fall
back to base Metal (grey "plastic") in Play/live. So the entire MG-Rust rust pass (walls/ceilings/stern,
~91 parts) is Studio-only and cannot ship as-is. Options put to Razvan: (A) built-in CorrodedMetal
[reliable, recommended], (B) re-upload textures under game owner + rebuild variant [needs source files
+ rights], (C) find a free/distributable Creator-Store rust material.

**RESOLVED (same session): the ownership theory was WRONG — MG-Rust renders in Play fine.** Razvan
confirmed the door/wall rust now loads in playtest and players see it. The actual fix was the earlier
`StreamingEnabled = false` (the "plastic" was streaming async-load of the MaterialVariant, not an
ownership block). No material swap needed; MG-Rust 30 stays on all ~91 surfaces. Only lingering
caveat: Studio playtest runs under the dev account, so worth eyeballing once on a PUBLISHED live server
that the foreign-owned textures also load for other players. Lesson: verify MaterialVariants in Play,
and don't jump to a pessimistic asset-ownership conclusion before ruling out streaming/async load.

**Captain's-desk props: swapped primitive "plastic boxes" for mesh models (Section 4).**
The desk props are code-generated by `MapBuilder` (officer block, was lines 722–727) and rebuilt every
server start by `MapBuilder.Dress()` (clears all `DD_*`, rebuilds), so they can't be fixed by hand-editing
the tree — must change the builder. Done:
- Inserted two trusted free Creator-Store models, cleaned them, and stored as templates in
  **`ServerStorage.DeskProps`**: `Lamp` (Model, EndorsedModel asset 360916895 — stripped its Script/
  ClickDetector/Sound, disabled built-in SpotLight, bulb→Neon) and `Mug` (MeshPart, sleitnick asset
  1237820787, tinted). Rejected a 100-part book stack and a scripted wall photo frame.
- Rewrote the officer desk block (`MapBuilder`, now ~lines 722–773): a `_placeDeskModel` helper clones
  `ServerStorage.DeskProps.<name>`, scales it, snaps its base to the desk top (y=3.0) via GetBoundingBox,
  anchors + parents to the section `DD_Dressing` as `DD_OLamp`/`DD_OMug`. Each has a **primitive fallback**
  (original ddPart/ddCyl) if the template is missing. Lamp gets a warm PointLight (0.8/9) on its bulb
  (re-implements old line 727). Books → a tidy 3-box tilted stack (muted leather tones); photo → a single
  tilted Wood frame. Fuse pickup + papers/ink untouched.
- Verified via `run_test` (play): no errors, §4 DD_Dressing rebuilds `DD_OLamp`=Model (19 desc),
  `DD_OMug`=MeshPart, 3×`DD_OBooks`, `DD_OPhoto`; lamp bbox base sits exactly on the desk. Also mirrored
  into the edit tree + screenshotted (temporarily boosted Lighting, then RESTORED it) — reads as a real
  lamp/mug/books/photo, big upgrade from boxes.

**NEEDS CTRL+S** — the `MapBuilder` source edit AND `ServerStorage.DeskProps` (Lamp+Mug templates) must
be saved, or the published game falls back to the primitive boxes. Meshes are from trusted distributable
creators (EndorsedModel/sleitnick), but per the MG-Rust lesson, worth one live-server eyeball. Tunable if
Razvan wants: lamp angle, book colors, model scale (`_placeDeskModel` scale args 0.9 lamp / 0.8 mug).

---

## 2026-07-02 — Claude (Razvan session) [Supporters wall]

**Renamed the wall board title + added auto-cycling pagination.**

The board is built at RUNTIME by `MapBuilder.dressSurvivorsWall()` (it is NOT in the saved tree — it's
a `DD_*` part that `MapBuilder.Dress()` destroys + rebuilds every server start), on the bow wall of
Section 1, tagged `SurvivorsWall` with a `Names` TextLabel that `MonetizationManager` fills with
Supporter Pass owners. This is why it's invisible in Studio's edit tree and only appears on Play.

- `MapBuilder` (~line 1182): board title `wtitle.Text` "SURVIVORS" → "SUPPORTERS". Instance name
  `DD_SurvivorsWall` and tag `SurvivorsWall` left unchanged (referenced by MonetizationManager).
- `MonetizationManager.renderSurvivorsWall`: rewrote to paginate — 8 names/page with a "·  p / n  ·"
  footer when >1 page. Added an auto-cycle loop in the wall's Start spawn that advances the page every
  6s when there are >8 supporters. Chose auto-pagination over scrolling because a world SurfaceGui
  isn't reliably scrollable in a first-person game.

Verified: run_test (play boot) PASSED — wall builds, title reads "SUPPORTERS", Names label present
("No supporters yet." when empty), 0 script errors. Multi-page cycling not exercised with real data
(needs >8 supporters). **NEEDS CTRL+S / republish.**

---

## 2026-07-02 — Claude (Razvan session)

**Developer Commentary: moved the run-rating webhook to a server-only Roblox Secret + fixed a false-confirmation bug.**

Context: the feature was already code-complete in the live place (commentary pass id `1899348664`,
`HttpService.HttpEnabled = true`, client `EndingClient` submit panel, server `onSubmitRun`) but the
webhook was unset AND declared in `ReplicatedStorage/Shared/MonetizationData` — a client-replicated
module, so a real webhook URL there would have leaked to exploiters.

Changes (live place 95779056096948):
- `Shared/MonetizationData`: removed the `DevRatingWebhook` field (old lines 69–71), replaced with a
  note pointing to the Secret. `DiscordInvite` kept (public, client-safe).
- `Server/MonetizationManager`: `onSubmitRun` now reads the webhook from a server-only Roblox Secret
  via `HttpService:GetSecret("dev_rating_webhook")`, POSTs with `RequestAsync` (JSON), and checks
  `resp.Success`. Added a `postRating()` helper + `DEV_RATING_SECRET` const (line ~255).
  Bug fix: the player used to be told "Your run was sent… Thank you" even when the webhook was empty
  and the run was dropped — now it only confirms on a real 2xx, and on failure it resets the 30s
  debounce so they can retry.
- Verified no client script referenced `DevRatingWebhook` (searched EndingClient + MenuUI) before
  removing it, so the removal can't break the client.

Verification: `manage_studio run_test` (play boot) PASSED — MonetizationData loads (webhook field
gone, commentary id present), MonetizationManager compiles + requires cleanly; `manage_logs errors`
returned 0 errors.

TODO for Razvan: (a) create a Discord webhook on the new server's `#run-ratings` channel; (b) Creator
Hub → this experience → Secrets → add key `dev_rating_webhook` = the full webhook URL (never paste it
into a script); (c) optionally set `MonetizationData.DiscordInvite`. **NEEDS CTRL+S.**

Update (same day): secret `dev_rating_webhook` added by the experience owner. Confirmed the webhook
FAILS in Studio ("Can't find secret with given key") — Roblox does not serve secrets to Studio
playtests, even in a fresh session. Verified it WORKS in a **published live server**: added a temp
`ServerScriptService/__DDWebhookTest` Script (live-only, one POST on server start), published, joined
live → message landed in the Discord `#run-ratings` channel. Temp script has been **deleted**;
re-publish to push the removal. Takeaway: the Dev Commentary webhook can only be validated live, not
in Studio.

---

## 2026-07-01 — Claude (Razvan session)

**Feature: "Skip intro cutscene" checkbox on the main menu.**

Client-only change, one script: `StarterPlayer/StarterPlayerScripts/Client/MenuUI` (LocalScript).

- Added a **session-only** `skipIntro` flag + a checkbox row on the `mainMenu` frame
  ("Skip intro cutscene", positioned just above the button stack). Toggling flips the flag
  and shows/hides a ✓. Not persisted — resets to OFF on every fresh join, so a player's
  **first** descent of a session always shows the cutscene (per Razvan's spec). The skip only
  takes effect once ticked in the menu.
- Refactored the post-prologue handoff into a `releaseToGameplay()` helper
  (stopDrift → camera Custom → controls on → HUD on → menu gui off).
- `play()` now branches: if `skipIntro`, it fires `StartRun`, stops menu ambience, and calls
  `releaseToGameplay()` directly — it never sets `DD_PlayPrologue`, so `ReplicatedFirst.IntroScreen`
  is never triggered and the ~15s 3-line prologue is skipped. Default path unchanged.

Why it's safe to skip the prologue's black screen: the `StartRun` handler
(`ServerScriptService/Server/EndingManager`, line ~416) only flips the per-player `InMenu`
attribute to false — no teleport/respawn. The character is already spawned in the sub (and on a
post-death "Main Menu → Play", `ReturnToMenu` → `ResetRun` already did `LoadCharacter()` before
showing the menu), so there's nothing to cover with a fade.

Verification: full source read-back OK; `manage_studio run_test` (play mode, 10s boot) passed with
no script errors. Live client-GUI/visual click-test not done via MCP (client GUI isn't
introspectable from the server-bound plugin during Play) — worth an eyeball in Studio.

Not touched: `IntroScreen`, any server script, settings persistence.

**Feature: main-menu background photo.**

Same script (`MenuUI`). Added a full-screen `ImageLabel` named `MenuBackground` as a child of the
`mainMenu` frame, created right after `mainMenu` (before the vignette). `ZIndex = 0` so it renders
behind the vignette / title / buttons / skip-intro row; `ScaleType = Crop` (cover-the-screen, no
distortion). `Image = rbxassetid://102522616858545` — Razvan's uploaded Image asset (assetTypeId 1,
owner RO_Razvan/639799162, uploaded 2026-07-01). Covers the animated 3D MenuScene backdrop while the
menu is up; the image hides with the main menu when a panel (Records/Store/Settings/Credits) opens.

Verification: `run_test` (play, 8s boot) passed, no script errors. Asset confirmed valid+owned via
`manage_assets info`. Live render not confirmable via MCP (client GUI not introspectable during Play,
and `execute_luau` can't run the yielding `PreloadAsync`) — needs an eyeball in Studio for framing +
text legibility. If the photo is busy/bright, a dim scrim over it may be wanted for button contrast.
