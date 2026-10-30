# Deep Descent — Work Log

Newest entries at top. Append a dated entry every working session; never overwrite older ones.
Be factual — give script/instance paths, and for tuning changes give old → new values.

> Note: this file was recreated on 2026-07-01 because the `DevLog/` folder was missing on
> this machine. If an older `WORKLOG.md` exists elsewhere, merge these entries back into it.

---

## 2026-10-30 (later) — Claude (Razvan session) [Save and GitHub push; Razvan publishes]

- Razvan reported not seeing the changes on their laptop, then tested again and confirmed they work. Publishing is left to Razvan.
- No game code changed in this entry. All 35 game scripts in Studio match `src/` byte for byte. FreezeCreature=false, Debug=false, StreamingEnabled=false, QualityLevel=Automatic.
- **Open, not investigated further:** the overhaul screenshots were taken with QualityLevel pinned to Level15. In a real run at Automatic on this laptop (GTX 1650 + AMD integrated; display on the AMD), the §1 spawn view was almost black, showing only red strips. The same spot at Level15, from a slightly different camera angle, showed lit rust walls. The Automatic shot was about 4s after spawn with the flashlight off, so it may not be the settled look. Players on Automatic may see much less of the dressing than the screenshots show.

---

## 2026-10-30 — Claude (Razvan session) [Visual overhaul: batches 3a–6 finished, flooding/doors/reset re-tested]

No assets inserted or uploaded. Saved in Studio with Ctrl+S; **not published**. All values below live in the place and in `src/`.
Screenshots: `DevLog/visual-audit/2026-10-30-final/`.

**`ServerScriptService/Server/MapBuilder`** (1649 → 2670 lines; everything built in `Dress()`, no hand-placed parts):
- `ddPart` now sets `CanTouch=false`.
- **Hull (3a/3b):** `dressArch`, `dressFrames`, `pipeRun`, `dressPipes`, `dressCableTray`; `dressIndustrial(folder, cx, i)` replaces the old version. Ribs at `FRAME_OFFSETS` every 6 studs, pipe bundles, valves, gauges, sagging cable Beams.
- **Doors + frames (3c):** `dressBulkheadDoors`, `dressDoorFace`, `dressDoorFrames`. The `BulkheadDoor` part is now an **invisible logic part**; the visible `DD_DoorLeaf` slides on the client. Stencilled `WTD n`, hazard headers, `DD_SealBar` X shown when `Sealed`.
- **Room machinery (3d):** `dressTorpedoRoom` (tubes laid horizontally through the bow wall), `dressBerthingDetail`, `dressGalleyDetail`, `dressOfficersDetail`, `dressControlRoom`, `dressSonarDetail`, `dressEngineRoom` (generator reskin, flywheel, status panel bound to `Running`), `dressAftDetail`. Screens bound to game state: ballast → `FuseInstalled`, radio → `Locked`.
- **Grime (2b):** `wallGrime` SurfaceGuis (tide band, salt line, streaks), room signs, warnings, three scrawls: §2 "DON'T RUN", §6 "IT'S LISTENING", §8 "IT COMES WHEN THE LIGHTS DO".
- **Effects (4b):** `addDrip`, `addSteam`, `addSparker`, `dressEffects`, three shaft Beams at the §9 breach.
- **Tower (6):** `towerWindow`, `dressTower`. Round viewports with marine snow. On `Sighting`, a soft black band (`DD_SightMass`) eclipses the glass with 5 faint lights on its flank.
- `dressSurvivorsWall`: y 8 → **10.9** (the re-laid tube lids covered the bottom of the board).
- `dressTorpedoRoom`: `PodWindow` Glass, Reflectance 0.3 → **SmoothPlastic, 0.04, (12,20,28)** (the Glass mirrored the sky pale pink).
- Tweaks: DD_DoorLamp y → DH+1.5; DD_StoveRing y → 3.3; lantern bounce 0.6 → 1.0.

**`ServerScriptService/Server/CreatureManager`** (`spawnCreature` rewritten, batch 5): invisible logic root, faceless ellipsoids + Beams (8 tentacles, 2 forelimbs, 4 gills, 5 spines, lure stalk). `SetState` sets attribute `State`.
- Body material: **Neon (5,6,8), Transparency 0** (near-black, unlit). SmoothPlastic, Slate, Fabric and CorrodedMetal all washed out pale under the flashlight whatever their colour, which looked like a white egg. Unlit, it reads as a moving void and looks the same at every quality level.
- Sizes: Head (3.5,3,4.6), Snout (2.3,1.7,3.2), Hump (2.7,4.2,3.1), Thorax (3.8,5.8,3.8), Belly (3.1,5.2,3.2), Tail (2,3.6,2.2). Gill Width0 1.5 → 0.55 (they read as paper triangles).

**`StarterPlayer/StarterPlayerScripts/Client/WaterRenderer`** (client side of all of the above):
- Water (4c): surface (58,96,106); volume transparency now `0.78 - 0.5*depth` with depth = clamp(level/45), so shallow floors stay visible under the torch; colour (26,60,66) → (4,16,24) with depth. Foam strips, 7 debris pieces per room, ripple emitters at drips, soft bubbles. Animates only within 75 studs of the camera.
- Underwater motes + breath bubbles on a `mouth` attachment.
- World animation: door slide (`DOOR_SLIDE` 7.5, 0.85 s tween on `Open`), flywheel on `Running`, `DD_Blink` LEDs, sonar sweep, tower sighting (18 s), creature limb sway + lure pulse (faster when `State == "hunting"`).

**`ServerScriptService/Server/PolishManager`:** breach spray gets the soft texture, Rate 80 → 26; `decorateWaterVents` removed; `decorateSpark` hooks `DD_Sparker` (flash light + sound); tower sighting fires on first §7 entry, then every 50–120 s while you linger.

**`ServerScriptService/Server/InteractionManager` / `FloodManager`:** removed `door.Transparency` writes (the logic part stays invisible).

**`ServerScriptService/Server/PowerManager.Reset` (bug fix, not visual):** now resets generator `Running`, stops `Snd_generator_hum`, relocks the radio and clears `FuseInstalled`. Before this, the radio stayed unlocked and the hum kept playing after Try Again.

**`StarterPlayer/StarterPlayerScripts/Client/FlashlightController`:** dust gets the soft dot texture (the default particle texture is a star).

**`StarterPlayer/StarterPlayerScripts/Client/MenuUI`:** `menuButton` restyled (dark, Oswald 22, thin rust stroke, 4 px rust left bar, hover tween).

**Tested in a real run (PLAY pressed, Studio):**
- Flood: all 8 water volumes rise. Door 1-2 open: §1 and §2 equalised (1.84/1.85 → 1.93/1.93). Close works. Leaf slides 7.5 studs and back; `CanCollide` follows `Open`.
- Seal door 2-3: `Sealed=true`, bars show, both prompts disabled.
- Generator: `Running`, radio unlocks, hum on, 15 main lights lit.
- `RequestResetRun`: generator off, hum off, radio locked, 0 main lights, seal cleared and bars hidden, water back near start levels 5 s later (§8 already at 1.65 against a 0.96 start, because the character stood in it and it floods fast once discovered).
- Console clean except the usual Studio DataStore warning. `FreezeCreature` and `Debug` are false. `StreamingEnabled` false.

**Counts in Play (emergency circuit):** parts 3012, enabled lights 41, shadow casters 9, emitters 78, SurfaceGuis 128, beams 61. **Parts are over the ~2100 planned.**

**Not verified:**
- Frame rate on a real PC or phone (Studio numbers aren't representative).
- Motion overall: door slide feel, limb sway, the sighting pacing. Only stills and state readbacks were checked.
- Drip ripple rings (`explosion01_shockwave_main.dds` path) were never seen on screen.
- The final tower colour and light-size tweak (gradient (13,42,60) → (18,54,76), lights about 30% smaller) wasn't re-shot.
- Level01 was checked in §3 only, before the creature went Neon.
- Co-op and anything needing a published server.

**Still open:** the creature can wander into §1 while dormant, although CLAUDE.md says it never *starts* there (noted earlier, unchanged).

---

## 2026-10-11 — Claude (Razvan session) [Visual overhaul batch 4a: flashlight]

**`StarterPlayer/StarterPlayerScripts/Client/FlashlightController`** (build v7 → **v8**, "core+spill"):
- Beam: one SpotLight (Angle 30, Range 55, Brightness 5) → **Core** (Angle 26, Range 60, Brightness **14**) plus **Spill**
  (Angle 75, Range 32, 0.43 × core) on Attachment `SpillOrigin` (0, −0.35, 0.3). Both stay always-enabled; brightness drives them.
  The `FlashlightColor` cosmetic tints both. Low-battery flicker unchanged.
- NEW near-surface dimming: one raycast/frame along the beam; within 6 studs brightness scales down to 35% (no white
  blow-out on glossy screens point blank; verified 14 → 8.7).
- Dust: an emitter riding the camera (Rate 10, flat dots) → a box volume `FlashlightDust` (10×7×16) kept 9 studs ahead,
  Rate 30, LightInfluence 1 (motes only show where lit: they sparkle in the beam). Always on (~30 particles/s).
- In-hand torch: + 5 rubber knurl rings, tail cap, neck, bright bezel, pocket clip (8 → 14 parts).
- Feel: the beam's aim trails fast turns by ~60 ms (lerp dt×16) and the model bobs with walking speed.
**Found, not fixed (→ batch 4c):** every room's floor sits under the dark water volume (WaterRenderer, (12,36,48) at ~0.35
transparency), which swallows the beam: floors read near-black even under the torch.
Verified: Stop→Play console clean, values read back, A/B in §6 radio half (dim room) at Q15. Studio test learning: a brightness-3.5
spill was invisible on these dark wet PBR surfaces; Roblox spotlights need ~6+ here to read.

---

## 2026-10-11 — Claude (Razvan session) [Visual overhaul batch 2a: hull surfaces (walls, bulkheads, ceilings, floors)]

**Bug found:** every hull floor (`Floor`, `CorrFloor`, `TowerFloor`) was `Material=CorrodedMetal` with
`MaterialVariant="deepdescent_floor_grate"`, but that variant's BaseMaterial is **DiamondPlate**. A variant only renders
on its own base material, so the grate never showed and floors were plain built-in CorrodedMetal (the bright, noisy floor
from the audit). Also, every wall in every room was the same `MG-Rust 30` (blue paint with white flecks).

**`ServerScriptService/Server/MapBuilder`** — NEW `dressSurfaces(model, i)` (per section, called first in the Dress loop) and
`dressConnectorSurfaces()` (after the loop), tables `WALL_FINISH` / `SURF`. Runtime only: the baked parts keep their Edit values.
- Side walls (`WallZpos/Zneg`, `TowerWall*`, `CaptainWall*`): Metal + per-room variant. §1 MG-Rust 24 (dark steel, streaks),
  §2 32 (navy paint), §3 15 and §4 18 (cream paint, peeling), §5 28 (blue-grey), §6 29 (slate), §7 24, §8 14 (rust running
  down), §9 05 (rust with teal growth). Colour (54,60,66) → **(72,72,74)**; §3/§4 **(64,62,60)** (96 was tried: too bright under tungsten).
- Bulkheads (`EndWall*`, `SternCap*`) + connector walls (`CorrWall*`): **CorrodedMetal + `deepdescent_hull_rust1`** (riveted plate), (110,104,100).
- Ceilings (`Ceiling`, `TowerCeil`, `CorrCeil`): MG-Rust 30 → **MG-Rust 24**, (44,46,50).
- Floors: CorrodedMetal → **DiamondPlate** (the `deepdescent_floor_grate` variant now renders), colour (46,50,54) → (58,60,62).
- `dressSonarRadio`: partition `DD_Part*` → `deepdescent_hull_rust` (riveted rust plate), (100,96,92).
- Side effect: the §4 captain-wall hot specular streak from 1c is gone (different variant roughness).
- Unused/empty variants found (render flat grey): `deepdescent_hull_rust3`, `deepdescent_floor_grate1-3`, `deepdescent_console2-3`.

No new assets (only variants already in MaterialService). No light/part changes. Nothing reads floor material (footsteps
only check for Air). Verified: Stop→Play console clean, materials read back at runtime, quality Level01 still textured.
Before/after + a swatch board of all 32 MG-Rust + the deepdescent variants: `DevLog/visual-audit/2026-10-11-2a/`.

---

## 2026-10-11 — Claude (Razvan session) [Visual overhaul batch 1d: colour grades for emergency / main power / underwater]

**`StarterPlayer/StarterPlayerScripts/Client/WaterRenderer`** — NEW client colour-grade state machine (table `GRADES`,
`applyGrade`, `refreshGrade`). It tweens the server-made `DeepColorCorrection`, `DeepBloom`, `DeepAtmosphere`,
`Lighting.Ambient` and `UnderwaterBlur` locally:
- **emergency:** CC B −0.04 / C 0.22 / S −0.28 / tint (222,218,234); Bloom 1.0 / thr 0.9; Ambient (10,17,28).
  (Old grade B −0.05 / C 0.12 / S −0.25 / tint (190,215,235): the cool tint cut the red channel by ~25%.)
- **main:** CC B 0 / C 0.18 / S −0.12 / tint (255,236,212) (warm tungsten over navy shadows); Bloom 0.9 / thr 1.0.
- **underwater:** CC B −0.03 / C 0.08 / S −0.3 / tint (95,190,205); Bloom 1.3 / thr 0.75; Atmosphere Density 0.42 → 0.9,
  Haze 2.4 → 4, Offset 0.1 → 0.2, teal colour/decay (gives real short visibility indoors); blur 8 → **3**; Ambient (8,22,30).
- Transitions: under 0.25 s, surfacing 0.9 s; emergency→main 2.6 s after a 0.4 s delay (warms as the lamps strike);
  main→emergency (reset) 0.6 s. Listens to `PowerUpdate` (first client listener).
- `SubmergedOverlay`: the flat full-screen teal frame at 0.38 → a faint teal body (0.85) + 4 dark `UIGradient` edge frames
  (a vignette, 0.1), with **DisplayOrder −1** so the HUD stays above it, untinted.
- Fix: the submerged check no longer `return`s early when the head/section is missing (a death underwater could leave the
  underwater state stuck); reverb is only set on change.

**`ServerScriptService/Server/LightingSetup`** — boot values now = the emergency grade: `DeepColorCorrection` B −0.05 → −0.04,
C 0.12 → 0.22, S −0.25 → −0.28, tint (190,215,235) → (222,218,234); `Lighting.Ambient` (8,14,22) → (10,17,28).

Verified: Stop→Play console clean; client values read back per state (emergency at boot, underwater when the head is under,
back to emergency on surfacing, main ~3 s after a real generator start); quality Level01 main power readable.
Before/after: `DevLog/visual-audit/2026-10-11-1d/`. **Not verifiable in stills:** the blend timing itself.
Capture gotcha: `prompt:InputHoldBegin()` only triggers once the prompt is SHOWN, which needs the camera near it,
not just the character.

---

## 2026-10-11 — Claude (Razvan session) [Visual overhaul batch 1c: warm tungsten main power + staged switch-on]

**Correction to the audit entry below:** the baked MainLight SpotLights already had `Shadows=false` (Angle 100,
Range 34). The old source code says `true`, but the baked instances differ. So main power did NOT add 16 shadow casters:
it was 12 shadow casters on either circuit before 1b, and it is 9 now on either circuit.

**`ServerScriptService/Server/MapBuilder`** — NEW `dressMainLamps(folder, model, i, cx)`, called in `Dress()` after
`dressEmergencyLighting`. Each tagged `MainFixture` (baked 3×0.4×1 box at y=15.6, z=±6) becomes a caged pendant at
runtime: the fixture → 1.5×0.5×1.5 dark housing at y=14.1 (SpotLight kept: Face Bottom, Angle 100 → **105**,
Range 34 → **30**, off), plus `DD_LampStem`, `DD_Bulb` (Ball 0.6, child of the fixture, dark Glass while off) and
4 `DD_LampCage` bars. The +Z lamp of each room gets attr `MainShadows=true` and a `DD_MainFillAtt` attachment
(at (lampX, 13, 0)) with PointLight `MainFill` (Range 34, off). §6 lamps move off the partition line to cx−7 (+Z, sonar
half) / cx+7 (−Z, radio half).

**`ServerScriptService/Server/PowerManager`** (now requires `SectionData`):
- Main power colour: cool white (208,222,235) → **warm tungsten (255,196,140)**. SpotLight brightness 1.5 → **4.5**,
  MainFill **1.2**. The old `MainGlow` (white PointLight b2/r30 parented to every emergency fixture) and
  `setMainGlow` are REMOVED, as is the fluorescent `flickerLight`.
- NEW staged switch-on: when the generator catches (after the existing 5 s spin-up), rooms strike in order of hull
  distance from §8 (0.45 s per hop, +0–0.15 s jitter): 2–3 failed strikes → `electrical_spark` SoundCue (vol 0.35)
  → the room's red lantern(s) drop to **30%** (bounce fill off, lens dims, shadows handed to the work lamp) → the
  filaments warm from (255,110,40) to tungsten over ~0.7 s. The tower (no work lamps) keeps its lantern at full.
- NEW tungsten brown-outs: every 5–14 s each room's lamps sag together to 45–75% (warmer colour) for 0.12–0.47 s.
- Off (Start/Reset): every lamp dark, every lantern back to full output and its recorded shadows
  (`FullBrightness` / `CastsShadows` attrs, recorded the first time). A `mainGeneration` counter stops stale threads.
- Emergency flicker `level()` now scales the lens/cone by Base/Full brightness (dimmed lanterns flicker dimly).

**Numbers (main power on):** enabled lights 56, shadow casters **9** (8 work lamps + breach), parts 979 (+96 lamp parts).
Emergency power unchanged (9 shadow casters).

Verified: Stop→Play console clean; generator triggered through its real ProximityPrompt (client `InputHoldBegin/End`)
in frozen-capture mode; lamps lit, lanterns at 30%, shadows 9; Reset path checked (lamps/bulbs off, lanterns back to
3.0 + shadows). Screens: `DevLog/visual-audit/2026-10-11-1c/` (BEFORE = audit's old main-power shots). Quality Level01
on main power: readable. **Not verifiable in stills:** the strike/warm-up timing and the brown-outs (needs a real playtest).
Studio gotcha: after a Studio restart the Automatic quality dropped low and captures went black, so pin
`settings().Rendering.QualityLevel = Level15` while capturing (and restore Automatic).

---

## 2026-10-11 — Claude (Razvan session) [Visual overhaul batch 1b: per-room emergency lighting]

Goal: replace the single centred red PointLight per room (a flat monochrome wash) with a lit composition:
one shadow-casting "hero" lantern per room + bounce fill + shadowless practicals in each room's own colour.

**`ServerScriptService/Server/MapBuilder`**
- NEW `dressEmergencyLighting(folder, model, i, cx)` (+ helpers `dressLantern`, `practical`, `glowFrom`,
  table `HERO_LAMP`), called from `Dress()` for every section after the room dressing.
  - The baked, tagged `EmergencyFixture` is **moved at runtime** onto a side wall (y=11.5) and becomes the lens
    of a caged lantern: cap, base, 4 cage bars, wall plate and arm (`DD_Lantern*`). Lens: Neon, colour (255,52,30),
    attribute `LensColor`. It stays the tagged part, so PowerManager / PolishManager keep working.
  - Hero light: Brightness 1.6 → **3**, Range 34 → **38**, Shadows on (the room's only shadow caster).
    Per room (x offset from centre / wall): §1 −13/+Z, §2 +4/−Z, §3 −14/+Z, §4 −4/+Z, §5 +14/−Z, §6 −4/−Z,
    §8 +4/−Z, §9 +6/+Z. `FlickerCalm` per lamp: §1 1.6, §2 1.0, §3 0.6 (twitchy), §4 1.2, §5 1.4, §6 1.0,
    §8 0.5 (dying), §9 1.0.
  - Per hero lamp: `DD_LightCone` (camera-facing Beam from the lens to the floor, transparency 0.82→1) and
    `DD_Bounce` (shadowless PointLight under `DD_BounceAtt`, 7 studs into the room at y=2.5, Brightness 0.6, Range 30).
  - **Conning tower fix:** its EmergencyFixture sat at (224,15.4,0), inside §5's ceiling, so §5 was lit twice and the
    tower was black. It's now a small shadowless lantern inside the tower at (227,29,−1.5), Brightness 1.4, Range 16.
  - `DD_DoorLamp` neon strip (170,30,18) over every doorway, inside each room (no light; reads at low quality).
  - Practicals (all shadowless): §1 `DD_PodLamp` amber on the escape pod (1.4/9) + 4 `DD_TubeLamp` indicators;
    §2 `DD_BunkLamp` warm (0.9/7); §3 `DD_StoveRing` pilot-light glow (1.2/8); §5 nav + helm screens → Neon green,
    nav glow (0.8/8), `DD_BallastLamp` amber (0.7/6); §6 sonar screen → Neon green + glow (1.1/10);
    §8 generator panel glow amber (1.0/9). §4 `CaptainLight` Shadows true → **false**.
- `dressSonarRadio`: `DD_RadioFixture` light 1.6/34/shadows → **0.9/20/no shadows** (radio half stays dim).
- `dressBreach`: `DD_BreachLightAnchor` moved from b+(−1.5,0,0) to **b+(−4,5,0)**, above the start waterline (under the
  water it lit nothing); light (70,120,190) 1.5/18 → **(60,150,170) 2.2/26**, Shadows stay on. §9 now reads red bow
  against cold teal stern.

**`ServerScriptService/Server/PowerManager`** — `startEmergencyFlicker`: the lens colour (Lerp from (60,10,6) to
`LensColor`), the `DD_LightCone` beam brightness and the `DD_Bounce` fill now dim WITH the bulb; the wait between
bursts is ×`FlickerCalm`. Old fixtures without these attrs behave as before.

**Numbers (runtime, emergency power):** shadow-casting lights 12 → **9** (8 hero lamps + breach). Enabled lights 25 → 39
(+8 bounce, +6 practicals; all shadowless and short range). Parts 787 → 863.
**Not done yet:** main power (`setMainGlow` still parents its white MainGlow to the moved lanterns), reworked in 1c.

Verified: fresh Stop→Play, console clean; fixture positions/attrs read back; before/after for all 9 sections from the
same camera spots in a frozen world (`DevLog/visual-audit/2026-10-11-1b/`); quality Level01: rooms dim red but readable,
lanterns and door lamps visible, flashlight works.
**Capture gotchas found:** Studio only computes lights near the player's character, so the character has to be near the
camera for a valid shot (some black frames in the 2026-10-11 audit were artifacts). Captures need 3–6 s to settle after a
camera jump. Freeze the world for captures by staying in the menu (`InMenu=true`), disabling the `MenuUI` LocalScript at
runtime and hiding its GUI; the creature then can't kill and the water doesn't rise.

---

## 2026-10-11 — Claude (Razvan session) [Visual overhaul: audit + plan + batch 1a (post-FX cleanup)]

Goal: push visuals toward Pressure/Doors level. Plan approved by Razvan (phases 1–6; main power will go
**warm tungsten**; creature model edits in `CreatureManager` OK). Tools: official `roblox-studio` MCP
(Luau Edit/Client/Server, Play screenshots, start/stop Play); Weppy is on **Basic**.

**Audit (read-only):** every section shot in Play on emergency/main power, flashlight on/off, plus the
underwater and menu views. Screenshots and camera spots: `DevLog/visual-audit/2026-10-11-before/`. Main findings:
one centred red PointLight per room → monochrome red wash with black walls; main power = flat cool-white
wash; box hull; primitive props; underwater = 38% teal GUI overlay over the HUD; **12 shadow-casting lights
on emergency, 28 on main power** (all 16 MainLight spots have `Shadows=true`). At quality Level01 rooms are near-black.
Side note (not fixed): the creature was seen wandering §1 while Dormant, incl. ~10 studs from spawn at run start.

**Batch 1a — `ServerScriptService/Server/LightingSetup`:**
- NEW: at start, destroys the place's starter Lighting effects that were stacking on the Deep* set:
  `Lighting.Atmosphere` (grey, Density 0.3), `Lighting.Bloom` (I 1.0 / Size 24 / Thr 2.0), `Lighting.SunRays`,
  `Lighting.DepthOfField` (disabled). Exact name+class match only; client-made `UnderwaterBlur` and
  `DD_BrightnessCC` are untouched. The Edit-mode instances are left in place (removed at runtime).
- `DeepBloom`: Intensity 0.6 → **1.0**, Size 24 → **28**, Threshold 1.4 → **0.9** (neon lenses, LEDs and the
  creature lure get a soft halo; flashlight hotspot doesn't wash out).
- Result: Lighting children at runtime 11 → 7 (one Atmosphere, one Bloom). Lights/particles/parts unchanged.

Verified: fresh Stop→Play, Lighting = DeepColorCorrection, DeepDOF, DeepAtmosphere, DeepBloom(1.0/28/0.9), Sky,
UnderwaterBlur, DD_BrightnessCC; console clean (only the usual Studio DataStore warning). Before/after
from the same camera spots in one session: `DevLog/visual-audit/2026-10-11-1a/` (change is subtle: fixture
halo + slightly stronger LED/lure glow). Low-quality (Level01) shot included as the baseline for 1b.

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
