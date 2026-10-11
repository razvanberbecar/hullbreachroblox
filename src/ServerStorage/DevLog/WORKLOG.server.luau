--[==[  HULL BREACH — WORK LOG  =============================================
Newest entries at the top. One entry per working session. See sibling "README"
for conventions. Copy the TEMPLATE at the bottom for new entries.
Edit between the --[==[ and ]==]

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 63 — persistence hardening: load-failure guard + receipt de-dup]

Type: Fix (robustness) + Deep audit

Summary: Full pre-release re-audit (every manager, all shared data, Net, client scripts, clean boots).
Game boots/plays/ends/resets with ZERO script errors. Fixed the two persistence robustness gaps
Razvan asked for (commentary pass confirmed working via the dev_rating_webhook Secret, so left alone).

FIX 2 — DataStore load-failure guard (Server/DataManager). Root problem: getAsync returned nil for
BOTH "new player" and "read failed", so a transient GetAsync outage on join made a returning player
look new, and PlayerRemoving's saveAll then overwrote their real passes/cosmetics/progress with
defaults (permanent loss of PAID content). Now: getAsync returns (data, ok) with ok=false ONLY on a
genuine read failure (3 tries w/ backoff), load() flags the session loadFailed on any failed read,
and saveMeta/saveSlot skip while loadFailed (session runs READ-ONLY so it can't wipe good data).
SelectSlot also aborts if the target slot read fails. Gated behind IN_STUDIO (RunService:IsStudio())
so Studio playtests stay fast/in-memory and are NOT falsely marked read-only (Studio API is off).

FIX 3 — ProcessReceipt de-dup (Server/MonetizationManager + DataManager). Roblox can call
ProcessReceipt more than once per purchase; save_slot could be granted repeatedly (capped 3, but a
leak). Added DataManager.WasReceiptProcessed / MarkReceiptProcessed backed by a new DD_Receipts_v1
store (userId_purchaseId -> true). processReceipt now checks WasReceiptProcessed BEFORE granting
(ack without re-grant if seen), grants, then MarkReceiptProcessed. Fail-open on read error (player
still gets the item; residual double-grant only on a crash-between-grant-and-mark, capped for slots).

Verified in Play: clean boot both fixes; DataManager loads a profile; session NOT read-only in Studio
(AddSaveSlot mutates slots 1->2 => saves not blocked); WasReceiptProcessed returns FALSE for a
guaranteed-fresh key (getOk=false) so first purchases are never wrongly blocked, and TRUE for a key
already marked this session (dedup works via the write-cache). Dedup control-flow SKIPPED-when-seen /
GRANTED-when-new confirmed.

Audit notes (healthy): Net has no undefined remote refs anywhere; all 21 sounds sourced; all pickups/
6 journals/interactables wired; creature patrols (S7 tower excluded by design); adjacency symmetric;
MenuUI Play/prologue + purchase wiring correct; all ending cutscenes + death + reset run error-free.
Minor/left: dead remotes SealDoor(now unused)/InteractRequest(legacy); stale logs "Future mode" &
"assign SoundData.Ids". LightingSetup correctly uses LightingStyle=Realistic.

Notes: 2 scripts changed — Server/DataManager, Server/MonetizationManager. NEEDS CTRL+S.

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 62 — pre-release audit; the_deep breach re-wired]

Type: Fix + Audit

Summary: Razvan: pre-release, deep-test the map/endings, find anything not as intended, report.

FIXED (release blocker): the_deep ending was UNREACHABLE. The HullBreach (Section_9) had lost its
Interactable tag / Kind="breach" / BreachPrompt in the baked map (the "instances created in Play
evaporate" pattern), so onBreach could never fire. Re-added them in Server/MapBuilder.dressBreach
(runs every server start, idempotent via a "not FindFirstChild BreachPrompt" guard): AddTag
Interactable, SetAttribute Kind="breach", ProximityPrompt "BreachPrompt" ([E] "Swim out",
HoldDuration 1.2, MaxActivationDistance 9, RequiresLineOfSight false). ExteriorPassage cargo prompts
(TakePrompt T / ReturnPrompt E) sit 47 studs away so no [E] clash. Verified in Play: HullBreach now
Interactable+breach with the BreachPrompt; InteractionManager.Handlers breach registered;
EndingManager.Trigger live; clean boot. NEEDS CTRL+S (MapBuilder script edit).

AUDIT (everything else) — healthy: all 9 endings reachable + correctly triggered (bad endings fire
from Oxygen/Creature; secrets gated on 6 pages + cargo take/return); GameConfig FreezeCreature=false
+ Debug=false (release-correct); runtime audit found NO orphan interaction Kinds, all pickups valid,
6/6 journal pages present, creature spawns + patrols (~8 st/s), flood rises, all 9 sections have
adjacency; power/fuse/ballast gating correct; oxygen drown/sealed/regen correct (7 seal prompts ->
sealed_in reachable); reset/randomize restores + re-locks + re-rolls, pcall-guarded.

ALSO FIXED THIS SESSION (Razvan: "fix all"): (1) BALLAST ESCAPE SOFT-LOCK — Server/PowerManager.
installFuse now RE-OPENS the valve puzzle when ballastPower is already true (calls
EndingManager.BeginBallastPuzzle) instead of dead-ending on "already powered", so closing the puzzle
with [Esc] can't strand the surface-manually route. Verified in Play (wrapped BeginBallastPuzzle:
reopen fires when already powered). (2) Server/FloodManager — REMOVED the unvalidated client
"SealDoor" OnServerEvent handler (no client fired it; sealing stays server-authoritative via
InteractionManager's proximity-checked SealPrompt -> FloodManager.SealDoor). Closes the remote-seal
grief vector. (3) Server/EndingManager header comment corrected to "9 endings" + the_deep added to
the Bad list. Clean boot, 0 errors after all three.

LEFT AS-IS per Razvan: baked BallastClue sign "3-1-4-2-5" (intentional red herring vs randomized
seq); SOS 2-min timer; escape-pod exactly-3-components / no margin (intended pressure).

Notes: only Server/MapBuilder changed. NEEDS CTRL+S.

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 61 — galley notice board un-merged; hint room banner]

Type: Fix + Feature

Summary: Two Razvan asks: (1) the galley daily notice board still clipped a wall; (2) on buying a Hint,
show a little notice above the toolbar naming the room the next log page is in.

(1) Notice board merge. NoticeBoard sat at X=cx+8 (120); its left edge (player's left when facing it)
overlapped the vertical ring-frame rib DD_Ring2L at X 121.6-122.4. Moved it to cx+6 (118) = the viewer's
right, so the board panel now spans X 115-121 and the right frame edge (121.35) clears the rib (121.6).
Authoritative fix is in Server/MapBuilder.dressNotice line ~694 (nb.CFrame = CFrame.new(cx+6,...)) since
Dress() HARD-SETS the board X every server start; frame/brackets/DD_Poster derive from nb.Position so they
follow automatically. Also nudged the Build() makeInteractable + makeJournal source to cx+6 for regen
consistency (Build early-returns on the baked map). Live baked board + DD_Nb* frame/bracket parts moved -2
in the Edit datamodel too so the Edit view matches now (not only after a play). NOTE: the baked page-3
Journal is a FLOOR pickup at X~105, NOT actually pinned to the board (source/baked diverged long ago) — left
it where it was.

(2) Hint room banner. New Net event HintDirection (S2C). Server/MonetizationManager.giveHint now resolves
the next page's room via SectionData.SectionAtPosition(pos) + Sections[idx].name and fires it to the buyer
(alongside the existing beacon + follow-the-light notify). Client/HUD adds a HintDirection banner: an
auto-sized amber bubble anchored bottom-center at (0.5,0),(1,-146) — just above the 4-slot toolbar (slots
live at 1,-70..-134) — reading "Go to the <Room> — the next log page is there.", fades in 0.3s / out
after 8s, and is cleared instantly on InMenu.

Verified in Play: clean load (no script errors; only the expected StudioAccessToApisNotAllowed DataStore
warnings). Server: board X=118 after Dress(); SectionAtPosition maps every journal page to a sensible room
name. Fired a test HintDirection to the client → HUD banner Text set, TextTransparency 0, BgTransparency
0.2, positioned 1,-146 above the toolbar. Real hint still only fires on a completed purchase (published).

Notes: 3 scripts touched — Shared/Net, Server/MonetizationManager, Client/HUD — plus Server/MapBuilder and
live Edit-datamodel part moves. NEEDS CTRL+S. Banner text/timing/position are easy knobs at the end of HUD.

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 60 — Hint glow reworked into a real beacon]

Type: Fix

Summary: Razvan: the hint glow barely showed (~half a second) and vanished; make it glow whether the page
is underwater or not. Root cause: giveHint put a single translucent Highlight (FillTransparency 0.5, 6s)
on the TINY 0.6-stud journal-page part — in the dark / underwater / at distance that reads as a flicker.

What changed (Server/MonetizationManager.giveHint):
- Replaced the page-part Highlight with an independent ANCHORED neon beacon at the page position:
  a Neon orb + PointLight (range 30) + an AlwaysOnTop Highlight, gently pulsing, lasting 15s (Debris).
  AlwaysOnTop + neon + light => visible THROUGH water and walls, in or out of the flood, from across the
  sub. Named DD_HintBeacon, parented to Workspace (not Submarine, so Dress() never clears it),
  CanCollide/CanQuery=false. Follow-the-light notify text.

Verified in Play (injected probe; MarketplaceService.ProcessReceipt can't be invoked manually in Studio,
same as real purchases not completing here — so ran giveHint's exact logic in the game VM): next page =
idx 1, target Journal part found, beacon spawns at the page and PERSISTS past 2.5s (real = 15s) with the
light + AlwaysOnTop highlight.

Notes: 1 SERVER script (MonetizationManager). NEEDS CTRL+S. Duration/brightness/range are easy knobs at
the top of giveHint. Real hint only fires on a completed purchase (published game).

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 59 — Hint button: label "Hint", bind H (PC can't click)]

Type: Fix / UI

Summary: Razvan: label it just "Hint" (drop the price), and PC can't click it (first-person mouse is
locked to the camera). Bound it to H; touch can still tap.

What changed (Client/HUD, HintButton):
- Text now "Hint" (no price). On keyboard devices it reads "Hint   [H]" (UserInputService.KeyboardEnabled)
  so the keybind is discoverable; on touch it's just "Hint". Greyed state text "No pages left".
- Shared buyHint() wired to BOTH MouseButton1Click (works for touch/tap) and an InputBegan H-key handler
  (gameProcessed-guarded). Same guards: no-op while InMenu or JournalRemaining<=0.

Verified in Play: label "Hint   [H]", active with pages, greys to "No pages left" at 0. 0 errors.

Notes: 1 CLIENT script (HUD). NEEDS CTRL+S. H is free (F=torch, L=records, Ctrl/C=crouch, Shift=run,
E=interact, 1-4=slots).

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 58 — Hint = constant HUD button]

Type: Change / UI

Summary: Razvan: make the Hint a constant on-screen button (was a FIELD AID row inside the [L] overlay),
buyable as many times as wanted.

What changed:
- Client/HUD — NEW persistent "HintButton" (top-right, DeepDescentHUD). Visible only during play (hidden
  while InMenu); fires Net Purchase("product","hint") on click; repeatable. Greys to "All log pages
  found" (Active=false) when player attribute JournalRemaining <= 0, re-enables when pages remain.
  Reacts to InMenu / JournalRemaining attribute changes.
- Client/MenuUI — removed the old FIELD AID hint section from refreshRecords ([L] overlay); it's now the
  HUD button only. (The [L] overlay in play is just RECORDS/endings now.)

Verified in Play: 0 errors; button hidden on menu, visible+active in play, greys at JournalRemaining=0,
re-enables at 3. Server hint guard (never charge with nothing to reveal) still applies.

Notes: 2 CLIENT scripts. NEEDS CTRL+S. Client reloads on Stop->Play. Reposition via HintButton.Position.

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 57 — REVERTED breath-hold/composure (too hard)]

Type: Revert

Summary: Razvan: the breathing sounds the creature can hear + the breath-hold mechanic make the game way
too hard. Fully reverted the session-55 composure feature. KEPT everything else (adaptive creature, run
randomization, leaderboards, journal persistence, and the session-56 crouch close-sense fix).

Removed (back to pre-session-55 behaviour):
- Shared/CreatureData — dropped breathing_fast/breathing_panic/gasp from SoundIntensity.
- Shared/Net — removed the HoldBreath remote.
- Server/OxygenManager — removed breathePlayer + its loop call, the holding/lastBreath state, getCreature,
  the HoldBreath handler + removing-clears, and reverted stepPlayer's regen guard (`elseif not holding`
  -> `else`). Oxygen is purely drown/sealed/regen again.
- Client/SoundProducer — removed the [B] hold-breath input + updateBreath + the breath attributes/gasp.
- Client/AudioManager — removed the HoldingBreath mute branch + the BreathGasp gasp one-shot.
- Client/HUD — removed the breath meter.
The creature no longer hears breathing at all; the only sounds it hears are the originals (walk/run/
splash/swim/interact/heartbeat). CreatureManager.GetPosition() left in as a harmless getter.

Verified: Stop->Play, 0 compile errors; script_grep for HoldBreath / breathePlayer / HoldingBreath = no
matches. NEEDS CTRL+S.

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 56 — crouch made quiet again (too sensitive)]

Type: Tweak / Fix

Summary: Razvan: the creature is too sensitive to crouching steps — it should hear them only when you're
right next to it. Crouch emits NO footstep sound, so two things were giving a croucher away: the
close-range MOVEMENT sense (13 studs) and the new breathing attraction (up to 42 studs).

What changed:
- Shared/CreatureData.CloseSenseRadius 13 -> 5. Movement is only sensed point-blank now, so a crouch-
  sneak is safe unless you're basically on top of it.
- Server/OxygenManager.breathePlayer — early-return while crouch[player] is set: crouching steadies your
  breath, so no breathing sound is emitted (a quiet crouch-sneak no longer draws the creature at range).

Verified in Play (injected probes; client FireServer confirmed to reach the server via a dry-room
hold-breath oxygen-drain test): with crouch set first, a still crouching player 15 studs from the
creature stayed ALERTED (not hunting) — vs a STANDING player at 28 studs which got hunted from breathing
earlier. Ordering matters in the probe: breathing attracts within ~0.5s, so crouch must be set before
moving into range. 0 compile errors.

Notes: 1 shared + 1 server script. NEEDS CTRL+S. Tuning: CloseSenseRadius(5) in CreatureData; crouch is
now a full breath-silencer (like hold-breath but free + slow) — narrow it to a range check if crouch
feels too safe.

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 55 — adaptive creature + breath-hold/composure]

Type: Feature

Summary: Two dread systems. (1) The creature now REMEMBERS the player's hiding spots and checks them.
(2) Breath-hold/composure: hold breath to go silent near it, at an oxygen cost, with a gasp if you
hold too long. Pure sound-tension, no health bar. Folded into existing modules (no new files).

ADAPTIVE CREATURE (Server/CreatureManager):
- hideCounts[locker] tallied on each hide (toggleHide step-in). New goalLocker + pickFavoriteLocker():
  once ALERTED, resolveGoal sometimes detours straight to the most-used locker (chance
  0.25 + 0.12*(uses-1), capped 70% — escalates with reliance) instead of pickAlertedSection. It heads
  to the locker's exact X/Z (they line the side walls) so it looms right at it; on arrival it DWELLS
  ~2.5s (reused the idle `lingerUntil`) with a creature_breath SoundCue, then moves on. A player hiding
  there survives only by staying still + silent (heartbeat/breath still gives them away). New
  CreatureManager.GetPosition() (also used by composure). Reset() clears hideCounts/goalLocker/lingerUntil.

BREATH-HOLD / COMPOSURE:
- Shared/CreatureData.SoundIntensity += breathing_fast=1, breathing_panic=2, gasp=3.
- Shared/Net += HoldBreath (C2S).
- Server/OxygenManager — breathePlayer(p,dt) each tick: if the creature is near (<=42) or hunting
  (<=130) or you're panicked (oxygen <25% leaks out to 90), it emits breathing_* via
  CreatureManager.ReportSound => louder breathing DRAWS it in. Holding breath (HoldBreath) emits nothing
  but drains oxygen at HOLD_DRAIN=2.5/s AND stepPlayer's regen is skipped while holding. Breathing
  emission gated to every 1.2s. (No new death type — over-hold just costs air; the client gasp is the
  betrayal.)
- Client/SoundProducer — HOLD [B] to hold breath (7s max, 3s cooldown after a forced gasp). Sets
  HoldingBreath + BreathFrac attributes and fires HoldBreath; on running out it fires SoundEvent("gasp")
  (creature hears it) + bumps BreathGasp. Recovers breath in ~5s when released.
- Client/AudioManager — mutes all breathing loops while HoldingBreath; plays a breathing_panic one-shot
  gasp when BreathGasp bumps.
- Client/HUD — subtle breath meter (bottom-centre, above oxygen), visible only while holding/recovering,
  driven by the BreathFrac attribute (turns amber under 30%). Not a health bar.

Verified in Play (injected probes; execute_luau is VM-isolated so can't read module locals): 0 compile
errors on all 7 scripts; a still, anchored player 28 studs from the creature (no footsteps, outside
close-sense) got it HUNTING purely from breathing; holding breath in a dry spot DROPPED oxygen instead
of regenerating (drain + regen-suppression confirmed) while the creature stayed dormant (silenced).
NOTE the drain magnitude in-probe was inflated by the long-running flood sim submerging the test spot;
HOLD_DRAIN=2.5/s is the real rate.

Notes for the team: 2 shared + 2 server + 3 client scripts. NEEDS CTRL+S. Client reloads on Stop->Play.
Tuning knobs: CreatureManager pickFavoriteLocker chance + 2.5s dwell; OxygenManager HOLD_DRAIN /
BREATH_NEAR(42) / BREATH_FAR(90) / BREATH_INTERVAL(1.2); SoundProducer HOLD_MAX(7)/HOLD_COOLDOWN(3) +
the [B] keybind. Breathing/gasp are audible only with the real breathing_* assets (already set).

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 54 — run randomization + leaderboards]

Type: Feature

Summary: Razvan: "same sub, different nightmare each time" + grind leaderboards. Built both.
NOTE: safe combo & radio frequency were dropped on purpose — they are NOT puzzles (onSafe just
opens, onRadio just broadcasts on main power); the only real "combination" is the ballast valve order.

RUN RANDOMIZATION (folded into EXISTING modules — no new files, Team-Create drop hazard):
- Server/EndingManager.randomizeRun() (local) — runs once at boot (after snapshotWorld) and again on
  every ResetRun (after restoreWorld + manager resets), so a reset re-rolls the shared world for
  everyone (consistent with restoreWorld already respawning shared collectibles). Does 4 things:
  (1) ITEMS/JOURNALS: permutes pivots WITHIN each pool (GetTagged Pickup/Journal, Workspace-only so
      ServerStorage snapshot templates are excluded). Flashlight/keycard/fuse are FIXED (flashlight =
      guaranteed first tool; keycard->fuse gate kept intact). Permutation = every target is an
      existing valid spot, so no page floats and no route soft-locks.
  (2) CREATURE START: CreatureManager.SetStartSection(rand of {3,4,5,6,8,9}) — new hook; repositions
      the live creature + aligns patrolPos. Never section 1 (spawn) so no instant death.
  (3) BREACH ORDER: FloodManager.SetRateMultipliers — new RateMult[section] applied in sectionRate();
      bounded 0.6x..2.5x per section, spawn room 1 capped <=1.0 so you're not drowned on wake.
  (4) BALLAST: shuffles {1..5} into activeBallast (BeginBallastPuzzle/onBallastInput now read it, not
      EndingData.BALLAST_SEQUENCE) and builds per-position CLUES seeded onto journal pages 1-5.
      EndingManager.GetBallastClue(pageIdx); InventoryManager.onJournal appends the clue to the page
      text on read. So the surface-manually valve order is pieced together by finding the log pages
      (pages 4-5 sit behind the keycard gate — matches progression). Page 6 stays clean.
  Verified in Play (injected probe Script — execute_luau is isolated in Play, can't see game VM/_G):
  creature start=section 5; ballast p1 "crack valve 2 first" / p3 "third, always the 3" (clues match
  the shuffled seq); flood mults 1.00,1.20,1.73,1.42,1.58,1.23,1.74,2.48,1.24; 0 errors.

LEADERBOARDS (menu button, GDD-style grind):
- Shared/Net — NEW C2S RemoteFunction GetLeaderboards.
- Server/EndingManager — run TIMER: runStart[player] set on StartRun + at end of ResetRun; on
  Trigger() computes elapsed and calls DataManager.RecordRunResult(player, endingId, elapsed).
- Server/DataManager — 3 OrderedDataStores (DD_LB_Endings_v1 desc, DD_LB_Survival_v1 desc, and
  DD_LB_Escape_<id>_v1 asc PER completing ending: escape_pod/sos_signal/surface_manually/the_truth/
  hubris). Account-wide bests tracked in meta.records (mostEndings/bestSurvival/bestEscape[id]); only
  improvements are pushed. GetLeaderboards() returns top-10 of each (GetSortedAsync + name resolve),
  cached 30s. "Longest SOS survival" implemented as LONGEST SURVIVAL (total run seconds, win or lose).
- Client/MenuUI — NEW LEADERBOARDS button (order 4; Settings/Credits bumped to 5/6, btnHolder 287->314,
  skip-intro row -297->-324) + panel (refreshLeaderboards): sections LONGEST SURVIVAL, MOST ENDINGS
  UNLOCKED, then FASTEST ESCAPE — <ending> per category. Empty boards show "No entries yet."
  Verified in Play: buttons PLAY|ENDINGS LOG|STORE|LEADERBOARDS|SETTINGS|CREDITS, panel present,
  GetLeaderboards round-trip ok (5 escape categories, empty in Studio — no DataStore API).

Notes for the team: 6 SERVER/shared + 1 CLIENT script. NEEDS CTRL+S. Client reloads on Stop->Play.
Leaderboards only POPULATE in the PUBLISHED game (Studio API access off — pcall-guarded, no errors).
Randomization re-rolls per run for the whole server (shared world). Journal pages now PERSIST in the
world after reading (InventoryManager.onJournal no longer Destroys them; collect counts once via a
firstRead guard) so the player can walk back and re-read the ballast-code clue any time.

----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 53 — survivors wall moved to the bow wall (opposite the aft door)]

Type: Tweak / Fix

Summary: Razvan couldn't find the survivors wall. Audited the whole place against this log first:
NOTHING from the log had been lost — all session-52 scripts, the baked map, code-driven decor, audio
ids, and monetization ids are intact and the wall builds fine at runtime (Names="dmakervd"). The real
issue was placement + where he was looking: (1) it's code-driven (Dress), so it does NOT exist in Edit,
only in a playtest after pressing Play past the menu; (2) session 51 had it at (-19,11,11.85) on the +Z
wall BEHIND the spawn and ~7 studs overhead. Razvan: "move it on the wall straight opposite to the door."

What changed (Server/MapBuilder.dressSurvivorsWall):
- CFrame (-19,11,11.85) -> CFrame.new(-23.8, 8, 0) * CFrame.Angles(0, math.rad(-90), 0). Section 1 is a
  box (floor X -24..24, Z -12..12); the DOOR is the opening in the +X aft end wall (EndWallL/R/Top gap
  at x=25, z -4..4). The wall straight opposite is the -X BOW wall (EndWall, interior face x=-24). Plaque
  now centered on it (z=0), Front face rotated to +X so it faces down the sub into the room, mounted at
  y=8 so its bottom (y=5.2) clears the torpedo-tube tops (y~4.7) -> unoccluded. Verified in Play: Front
  LookVector (1,0,0), Y span 5.2..10.8, Z span -4.5..4.5, inside room, Names="dmakervd", 0 errors.

Notes: SERVER (MapBuilder). NEEDS CTRL+S. Only visible in a PLAYTEST (press Play, then Play past the
menu), not in Edit. Nudge CFrame.new(-23.8,8,0) to reposition on the bow wall.


----------------------------------------------------------------------------
2026-07-02 — Claude (Claude Code)  [session 52 — Developer Commentary submit-run flow (upsell + notes + Discord)]

Type: Feature / Monetization

Summary: Built the Developer Commentary flow Razvan designed: on EVERY end screen (win or lose) an
"Ask for Developer Commentary" button; owners open a notes panel and submit, non-owners get an
upsell purchase prompt; after sending, a Discord invite is shown. Requests POST to a webhook.

What changed:
- Client/EndingClient — reworked the old owners-only good-ending-only rateBtn. Now shows on all
  endings (playCutscene sets ownsCommentary via GetGameState + reveals the button always). Click:
  owners -> openCommentary() modal (title, optional multiline notes TextBox, SEND); non-owners ->
  Net Purchase("pass","commentary"). A MarketplaceService.PromptGamePassPurchaseFinished listener
  (passId == Passes.commentary.id) flips ownsCommentary + auto-opens the panel after purchase. On
  SEND -> Net SubmitRun({ending,category,notes}); panel swaps to a "Sent — thank you" view with the
  Discord invite in a selectable TextBox (Monetization.DiscordInvite; hidden if blank). Requires
  MonetizationData + MarketplaceService (added).
- Server/MonetizationManager.onSubmitRun — now reads summary.category + summary.notes (capped 500)
  and includes journal pages (InventoryManager.GetJournalCount) + Win/Loss outcome in the webhook
  content; on PostAsync failure clears the 30s rate-limit + tells the player to retry.
- Shared/MonetizationData — NEW DiscordInvite = "" (public invite shown after submit; blank hides it).

Verified: Stop->Play 0 compile errors (client + server loaded). Fired SubmitRun from Client with
{ending="The Truth",category="good",notes=...}: reached onSubmitRun, passed the commentary-owned gate
(owner owns it in Studio) + rate-limit, assembled payload w/o error, hit the "DevRatingWebhook not
set -> dropped" branch (expected). Couldn't script-drive the end-screen UI (needs a real death/ending).

CONFIG NEEDED (Razvan): (1) paste the Discord WEBHOOK url into MonetizationData.DevRatingWebhook;
(2) paste the public INVITE into MonetizationData.DiscordInvite; (3) enable "Allow HTTP Requests" in
Game Settings > Security or PostAsync errors. Reply delivery is out-of-band (dev replies in Discord).

Notes: 1 CLIENT + 2 SERVER/shared scripts. NEEDS CTRL+S. Client reloads on Stop->Play. Only
Supporter "lobby badge" remains from the monetization plan.


----------------------------------------------------------------------------
2026-07-01 — Claude (Claude Code)  [session 51 — survivors plaque moved above the escape pod]

Type: Tweak

Summary: Razvan: put the survivors plaque above the escape pod, centered on that wall.

What changed (Server/MapBuilder.dressSurvivorsWall):
- CFrame (7,4.5,-11.7) -> (-19, 11, 11.85): now on the +Z wall (WallZpos interior face z=12),
  centered above the escape pod (EscapePodPanel ball at (-20,3.5,9), top y=7). board.Face Back->Front
  so the -Z display face points into the room. Verified: plaque bottom y=8.2 (1.2 stud gap above the
  pod), frontDotToRoomCenter=0.51 (faces room), Names="dmakervd", 0 errors.

Notes: SERVER (MapBuilder). NEEDS CTRL+S + Stop->Play. Nudge CFrame.new(-19,11,11.85) to taste.


----------------------------------------------------------------------------
2026-07-01 — Claude (Claude Code)  [session 50 — survivors wall moved from menu scene into the spawn room]

Type: Change / UI

Summary: The main menu draws a full-screen background IMAGE over the world, so the s48–49 menu-scene
survivors wall was hidden behind it (that's why Razvan couldn't see it). Razvan's call: make it a real
in-game object in the spawn room. Moved it there.

What changed:
- Server/MapBuilder — removed the survivors wall from BuildMenuScene. NEW local dressSurvivorsWall()
  builds a lit plaque (Part DD_SurvivorsWall, 9x5.5x0.3, SurfaceGui on the Back/+Z face, title +
  subtitle + "Names" label, faint PointLight) flush on the forward -Z wall of Section 1 at
  CFrame.new(7, 4.5, -11.7), tagged "SurvivorsWall". Called from Dress() (which ALWAYS runs, even on
  the baked map — unlike Build(), which early-returns; so buildProps couldn't have placed it). DD_*
  name = cleared/rebuilt idempotently each Dress.
- Server/MonetizationManager — renderSurvivorsWall now finds the wall via
  CollectionService:GetTagged("SurvivorsWall")[1] (not the old MenuScene path); Start's deferred
  initial render polls for the tagged wall (up to 20s) instead of waiting on MenuScene.

Why the spawn room works: StartSpawn = Workspace.Submarine.StartSpawn at (8,1,-7), identity rotation
=> player faces -Z toward WallZneg (interior face z=-12). Plaque at z=-11.7 with its +Z display face
toward the room sits ~5.9 studs dead ahead of the spawn.

Verified (Server execute_luau in Play): tagged wall at Section_1_forward_torpedo.DD_SurvivorsWall
pos (7,4.5,-11.7), Face=Back, Names="dmakervd", backFaceDotToSpawn=0.79 (faces the spawn), 0 errors,
dress log now "+ survivors wall".

Notes for the team: 2 SERVER scripts. NEEDS CTRL+S. Plaque is code-driven (Dress) so it survives.
Adjust CFrame.new(7,4.5,-11.7)/size in dressSurvivorsWall to reposition. DataStore persistence still
only works in the published game.


----------------------------------------------------------------------------
2026-07-01 — Claude (Claude Code)  [session 49 — survivors wall wasn't visible: repositioned + brightened]

Type: Fix / UI

Summary: Razvan couldn't see the survivors wall. Diagnosed with the CLIENT camera's
WorldToViewportPoint (screen_capture is blank here): the s48 wall WAS on-screen + rendering (Names
label "dmakervd"), but it sat too close/large so ~half wrapped off the left edge, it was a dark slab
on dark water, and the name text was tiny.

What changed (Server/MapBuilder.BuildMenuScene):
- Moved the plaque back + in: cam.CFrame*(-10.5,3,-21) -> (-11,2,-30); size 16x10 -> 18x11. Now all
  4 corners are on-screen (measured): spans ~11-48% X, ~32-62% Y, center (32%,47%), depth ~29 —
  left-center of the menu, in front of the sub, not clipped.
- Brightened so it reads against dark water: bg color 14,18,22 -> 26,34,44 @ 0.06 transparency;
  UIStroke 90,120,140/3px/0.3 -> 120,190,220/4px/0.1; Names TextSize 24 -> 32. (SurfaceGui already
  LightInfluence=0 = full-bright.)

Verified: Stop->Play; client WorldToViewportPoint shows all corners in-viewport; wall + Names render.

Notes for the team: SERVER script (MapBuilder) — menu scene rebuilds on Play. NEEDS CTRL+S, then a
fresh Stop->Play to see the new placement. Nudge cam.CFrame*(-11,2,-30) in BuildMenuScene to taste.


----------------------------------------------------------------------------
2026-07-01 — Claude (Claude Code)  [session 48 — Supporter survivors wall + Extra Save Slot store row]

Type: Feature / Monetization

Summary: Razvan: build the Supporter Pass perk (survivors wall) + add the Extra Save Slot to the
store. Edited existing scripts only (no new files — Team-Create drop hazard).

What changed:
- Server/MapBuilder.BuildMenuScene — NEW physical "SurvivorsWall" plaque part in MenuScene
  (16x10x0.4), a dark slab with a Front-face SurfaceGui (title SURVIVORS + subtitle + a "Names"
  TextLabel). Positioned via cam.CFrame * (-10.5, 3, -21) and oriented with CFrame.lookAt(wallPos,
  cam) so the Front face (normal = -Z = LookVector) points AT the menu camera. Verified in-frame:
  center 26.6deg horiz (<~51deg horiz half-FOV), 8deg up; frontFacesCam dot = 1.00.
- Server/MonetizationManager — NEW survivors list (ordered, unique) persisted to DataStore key
  "SurvivorsWall_v1" (best-effort; pcall-guarded, no-ops in Studio w/o API access). addSurvivor()
  called when a player is confirmed to own the supporter pass (checkPasses) and on
  PromptGamePassPurchaseFinished for supporter; renderSurvivorsWall() writes the Names label
  (newline-joined, or "No supporters yet."). loadSurvivors() + a deferred initial render on Start
  (waits for MenuScene). Server-owned label text replicates — no client wall code.
- Client/MenuUI.refreshStore — NEW "SAVE SLOTS" section: buys the save_slot dev product
  (PromptProductPurchase via Net Purchase("product","save_slot")); shows "All N save slots unlocked"
  once slots>=maxSlots. Auto-refreshes via the existing PromptProductPurchaseFinished listener.

Verified (Server execute_luau in Play): wall present at Workspace.MenuScene.SurvivorsWall, Board on
Front face, Names label = "dmakervd" (owner owns supporter in Studio -> proves the whole path).
0 script errors; DataStore StudioAccessToApisNotAllowed warnings (SurvivorsWall_v1 + PlayerData) are
expected in Studio and pcall-guarded.

Notes for the team: 2 SERVER + 1 CLIENT script. NEEDS CTRL+S. Survivors persistence only works in
the PUBLISHED game (Studio API access is off). Razvan: confirm the wall's on-screen placement live
(left of the menu, above the buttons) and nudge cam.CFrame*(-10.5,3,-21) in BuildMenuScene if needed.


----------------------------------------------------------------------------
2026-07-01 — Claude (Claude Code)  [session 47 — all 3 game passes now show in the STORE]

Type: Fix / UI

Summary: Razvan: Supporter Pass + Developer Commentary were missing from the store. Root cause:
the GAME PASSES loop in refreshStore still had the old `if pass.key == "nightmare"` filter, so only
Nightmare rendered. Client-only change (MenuUI).

What changed:
- Client/MenuUI (refreshStore, GAME PASSES) — replaced the nightmare-only filter with an ordered
  ipairs over { "supporter", "nightmare", "commentary" } so all three render in a stable order
  (pairs() was unordered anyway). Same Purchased-vs-buy logic per row.

Verified: Stop->Play 0 errors; GetGameState returns all three pass keys. (Couldn't script-click the
STORE button — Razvan confirm live: STORE now lists Supporter / Extended Nightmare / Developer
Commentary.)

REMINDER: Supporter Pass PERK (lobby badge / survivors wall) is still NOT implemented — buying it
grants ownership + shows "Purchased" but has no visible effect yet. Extra Save Slot product still has
no store row (the RECORDS save-slot section references it but there's no buy button).

Notes for the team: CLIENT script — reloads on Stop->Play. NEEDS CTRL+S.


----------------------------------------------------------------------------
2026-07-01 — Claude (Claude Code)  [session 46 — store shows Purchased / Equipped + auto-refresh on buy]

Type: Feature / UI

Summary: Razvan: after a purchase, refresh the panel so one-time items read "Purchased" and
equippable items read "Equipped". Client-only change (MenuUI).

What changed (Client/MenuUI, refreshStore):
- Now reads state.passes + state.cosmetics (already returned by GetGameState/DataManager.combined)
  alongside state.owned.
- GAME PASSES: owned pass renders a non-button row "<name>  —  Purchased ✓"; otherwise the buy
  button as before.
- Cosmetics (factored into a cosmeticSection(title, kind, list) helper for flashlight/suit/death):
  three states — Equipped ✓ (key == equipped[kind], default counts as equipped when unset) /
  "Owned — click to equip" / "Click to purchase". Clicking an owned item equips (CosmeticSelect)
  then task.wait(0.25) + refreshStore() so it immediately flips to Equipped.
- NEW refreshVisibleShop() + MarketplaceService.PromptGamePassPurchaseFinished /
  PromptProductPurchaseFinished listeners (client): on a successful purchase, wait 0.7s for the
  server grant to land then refresh whichever panel is open (store or [L] records), so bought
  items flip to Purchased/equippable without reopening. Added MarketplaceService to the services.

Verified: Stop->Play 0 errors; client GetGameState returns cosmetics={all default},
passes populated (owner owns passes in Studio -> proves the "Purchased ✓" path), owned={}.
Couldn't script-click store buttons (getconnections blocked) — Razvan confirm live: STORE -> equip a
beam -> row flips to "Equipped ✓"; a real pass purchase flips to "Purchased ✓" after ~1s.

Notes for the team: CLIENT script — reloads on Stop->Play. NEEDS CTRL+S. (Menu STORE still lacks
Supporter/Commentary/Extra-Save-Slot rows — still open.)


----------------------------------------------------------------------------
2026-07-01 — Claude (Claude Code)  [session 45 — in-run Hint buy: FIELD AID row in the [L] overlay]

Type: Feature / Monetization

Summary: Razvan chose the [L]-overlay trigger for the Hint product. Added an in-run buy affordance
that fires PromptProductPurchase for the hint dev product, greyed out when all pages are found,
plus a server guard so a player is never charged with nothing to reveal.

What changed:
- Client/MenuUI (refreshRecords) — NEW "FIELD AID" section at the top of the [L] overlay, shown
  ONLY during play (gated on player attribute InMenu ~= true, so it never appears under the main
  menu's ENDINGS LOG). If JournalRemaining <= 0 it renders a greyed non-button row ("Every page
  found"); otherwise a button "Locate the next captain's-log page (50 R$)" that fires
  Net Purchase("product","hint") and closes the overlay (gui.Enabled=false) so the glow is visible.
- Server/InventoryManager (pushJournal) — now sets player attribute JournalRemaining =
  #ItemData.JournalPages - collectedCount on every push (init / collect / reset), so the client can
  gate the button live without a GetGameState round-trip.
- Server/MonetizationManager (onPurchase, product branch) — for keyName=="hint", checks
  InventoryManager.GetNextJournalIndex first; if nil, notifies and returns WITHOUT prompting (never
  charge for a no-op hint). Authoritative gate; the client grey-out is just UX.

Verified: Stop->Play boot 0 errors; player attrs InMenu=true + JournalRemaining=6 at menu (so FIELD
AID correctly hidden in-menu). Next-page lookup + highlight already verified session 44.
NOTE couldn't fully drive the in-play overlay via automation (menu freezes until Play is pressed) —
Razvan should confirm live: press Play, [L], see "FIELD AID" row; buy flow needs the published game.

STILL OPEN (option 1): add Supporter + Commentary + Extra Save Slot rows to the menu STORE panel.

Notes for the team: 1 CLIENT + 2 SERVER scripts. NEEDS CTRL+S. Client reloads on Stop->Play.


----------------------------------------------------------------------------
2026-07-01 — Claude (Claude Code)  [session 44 — Hint product now points to the NEXT journal page]

Type: Feature / Monetization

Summary: Razvan: the Hint developer product should reveal the next captain's-log page instead of
the nearest random object. Reworked giveHint + added a query to InventoryManager.

What changed:
- Server/InventoryManager — NEW InventoryManager.GetNextJournalIndex(player): number? — the
  lowest-numbered page (1..#ItemData.JournalPages) the player hasn't collected, in narrative
  order; nil once all 6 are found.
- Server/MonetizationManager.giveHint — rewritten: resolves the next page via that query, finds
  the Workspace part tagged "Journal" with matching PageIndex attribute, and highlights it for 6s
  (parchment tone, DepthMode=AlwaysOnTop so it reads through the dark). Diegetic line now
  "Page N of the captain's log glows faintly through the dark." Graceful notify if all pages are
  already held (nothing to point to) or the part can't be found. Dropped the old nearest-
  Pickup/Journal/Interactable distance scan.
  (Collecting a page Destroys its part, so uncollected pages == the Journal-tagged parts still in
  the world — the lookup is naturally correct after collection/reset.)

Verified (Server execute_luau during Play): world has journal pages {1,2,3,4,5,6};
GetNextJournalIndex = 1 at run start; giveHint lookup -> Workspace.Submarine.
Section_1_forward_torpedo.Journal_1; Highlight applies with no error. 0 boot errors.

STILL OPEN (option 1 in progress): (a) no in-run TRIGGER to buy a Hint yet — need a buy affordance
(HUD button / [L] row / keybind) that fires PromptProductPurchase(hint.id) and should be gated off
when GetNextJournalIndex is nil; (b) still need to add Supporter + Commentary + Extra Save Slot
rows to the menu STORE panel (currently only nightmare + cosmetics shown).

Notes for the team: SERVER scripts — reload on Play. NEEDS CTRL+S.


----------------------------------------------------------------------------
2026-07-01 — Claude (Claude Code)  [session 43 — real monetization IDs wired into MonetizationData]

Type: Config / Monetization

Summary: Razvan created the 3 game passes + 8 developer products on the Creator Hub and sent the
asset IDs; pasted them into Shared/MonetizationData (the id=0 placeholders). Monetization is now
LIVE end-to-end — all backend was already wired (MonetizationManager / DataManager / ApplyCosmetics),
this just filled the IDs.

IDs set:
- Passes: supporter 1898226685, nightmare 1898220673, commentary 1899348664
- Products: hint 3607650035, save_slot 3607650337, amber 3607650440, cold 3607650551,
  green 3607650622, rust 3607650765, deep 3607650902, dragged 3607651017
- The three free defaults (beam/suit/death) correctly stay id=0.

Verified: Stop->Play boot, 0 monetization errors (DataStore StudioAccessToApisNotAllowed warnings
are unrelated — Studio API access off). Pass-ownership checks are pcall-wrapped so they can't throw.

KNOWN UI GAP (still open): the STORE panel only surfaces the nightmare pass + the 3 cosmetic
categories. supporter + commentary passes and the hint + save_slot products now have valid IDs but
are NOT reachable in the menu store (GAME PASSES loop filters to key=="nightmare"; Monetization.Products
is never rendered). My earlier "buy an Extra Save Slot in the Store" hint text has no matching button.
Needs a UI pass if those four are meant to be buyable from the menu. NOTE supporter's badge/survivors-
wall PERK is also not implemented (ownership tracked only).

Notes for the team: DATA module (MonetizationData) — reloads on Play. NEEDS CTRL+S. Real charges only
fire in the published game; as the game owner you won't be charged when testing prompts.


----------------------------------------------------------------------------
2026-07-01 — Claude (Claude Code)  [session 42 — main-menu STORE button; purchasables split out of the Endings Log]

Type: Feature / UI

Summary: Razvan: add a STORE button to the main menu and move all the purchaseable items that
lived in the Endings Log into it. Only Client/MenuUI touched.

What changed:
- Client/MenuUI — the single RECORDS panel used to hold Save Slots + Endings Log AND all four
  purchasable sections (Game Passes, Flashlight Beams, Diving Suits, Death Animations). Split it:
  * NEW makeScroll(panel) helper (factored the ScrollingFrame+UIListLayout scaffold).
  * NEW storePanel ("HULL BREACH — STORE") with its own storeScroll.
  * refresh() -> refreshRecords() (now ONLY Save Slots + Endings Log) + NEW refreshStore()
    (the four purchasable sections, moved verbatim). The row/sectionLabel/clearScroll helpers
    still close over the module-level `scroll`, which each refresh retargets (recordsScroll /
    storeScroll) before rebuilding — kept the helpers untouched.
  * Main menu now: PLAY / ENDINGS LOG / STORE / SETTINGS / CREDITS (btnHolder height 232 -> 287
    for the 5th button). showOnly() + storeClose->backToMain wired for the new "store" view.
  * Locked save-slot sub-text now points players to the Store ("buy an Extra Save Slot in the Store").
- In-game [L] overlay still opens the RECORDS panel (Endings Log); the Store is menu-only, matching
  the request. Cosmetic Purchase/CosmeticSelect remotes are unchanged — only the UI moved.

Verified: Stop->Play boot, 0 script errors; client GUI shows main-menu buttons in order
1:PLAY 2:ENDINGS LOG 3:STORE 4:SETTINGS 5:CREDITS. (Monetization IDs still 0 — see open gaps.)

Follow-up fix (same session): section headers rendered clumped at the BOTTOM instead of above
their rows. Cause: makeScroll's UIListLayout had no SortOrder, so it defaulted to SortOrder.Name
— sorting by instance name (all rows "Frame"/"TextButton" first, all labels "TextLabel" last),
ignoring the LayoutOrder the code assigns. Set `ll.SortOrder = Enum.SortOrder.LayoutOrder` in
makeScroll. This also fixes the RECORDS/Endings-Log panel (shares the helper). LESSON: any
UIListLayout that relies on LayoutOrder MUST set SortOrder = LayoutOrder (default is Name).

Notes for the team: CLIENT script (MenuUI) — needs a fresh Stop->Play to reload. NEEDS CTRL+S.


----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 35 — intro trimmed to 3 lines + opening black beat]

Type: Writing / Tweak

Summary: Razvan: shorten the opening prologue by 2 slides, and show a fully black screen before
the sentences begin. Only ReplicatedFirst/IntroScreen touched (items/restart files left alone).

What changed:
- ReplicatedFirst/IntroScreen — LINES cut 5 -> 3 (merged the mission/"they succeeded" beat into
  one, dropped the "hull broken / water climbing" line; kept "it followed them down" and the
  closing "it hears everything"). Added INITIAL_BLACK = 2.0s: the story coroutine now holds pure
  black for 2s before the first line fades in. Pacing per line unchanged (~5s). 0 errors at boot.

Notes for the team: CLIENT script — needs a fresh Stop->Play to reload. NEEDS CTRL+S.


----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 34 — flashlight/items didn't respawn on restart: RunReset module had vanished]

Type: Fix / Incident

Summary: Razvan: took the flashlight, got killed, restarted — the flashlight was out of hand
(correct) but did NOT return to its spot in §1. Reproduced: the s30 RunReset ModuleScript was
GONE from the tree, so no world snapshot was taken and RestoreWorld did nothing — i.e. NO
collected item respawned (the flashlight was just the one Razvan noticed). Fixed by folding the
snapshot/restore into EndingManager. Playtested, 0 errors.

Root cause: RunReset was a NEWLY CREATED ModuleScript that was never Ctrl+S'd. Team Create
dropped the unsaved insert (same hazard as the s17/s29 baked-decor reverts). Bootstrap still
listed "RunReset", so startManager just warned + skipped -> snapshot never ran -> nothing to
restore on Try Again / Reset.

What changed:
- Server/EndingManager — absorbed the world snapshot/restore (snapshotWorld + restoreWorld + the
  item/door/lock template state). snapshotWorld() now runs in EndingManager.Start() at boot;
  ResetRun calls the local restoreWorld(). Same behaviour as the old RunReset module, but living
  in an EXISTING script so an unsaved insert can't drop it again.
- Server/Bootstrap — removed the dead "RunReset" MANAGER_ORDER entry.

Verified (run_test): boot snapshot = 17 templates; take the flashlight -> taken -> ResetRun ->
the §1 Pickup_flashlight is back at its start spot AND hasFlashlight=false. 0 errors.

Notes for the team:
- LESSON: newly CREATED ModuleScripts do NOT survive without Ctrl+S in Team Create — unsaved
  inserts get dropped (just like baked parts). Prefer editing existing scripts; SAVE after adding
  any new file, and re-verify later.
- NEEDS CTRL+S (server-script edits). Reloads on Play.


----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 33 — intro prologue paced/fixed (was collapsing instantly)]

Type: Fix

Summary: Razvan: the opening black screen "just appears and disappears." Root cause: the s32
intro let any input skip it, and skipping collapsed every fade to 0.4s AND broke the holds.
In a playtest you click into the viewport / press a key to start, which tripped the skip ~1s
in and blasted the whole prologue past. Removed skipping entirely and slowed the pacing.

What changed:
- ReplicatedFirst/IntroScreen — removed the UserInputService skip + all "skipped" checks, so
  the holds (task.wait) can no longer be short-circuited. Each line is now ~5s on screen
  (FADE_IN 1.0 + HOLD 3.4 / last 4.2 + FADE_OUT 0.9 + GAP 0.35); ~29s total for the 5 lines.
  MAX_INTRO safety cap raised to 60s. Intro only plays once per join, so no skip is fine.

Verified: clean 8s boot playtest, 0 errors. (Visual timing is client-side — confirm on a fresh
Stop->Play.)

Notes for the team: CLIENT script (IntroScreen) — needs a fresh Stop->Play to reload. NEEDS CTRL+S.


----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 32 — journal lore rewrite + reader panel + expanded intro]

Type: Writing / Feature

Summary: Razvan: rewrite the in-room backstory documents (the 6 captain's journal pages) so
they make sense + build suspense + fix the broken/terse English, and add more backstory to the
opening black screen. Rewrote all six pages into a coherent escalating arc, gave journal reads a
proper readable page panel (the old one-line notify clipped long lore), and expanded the intro
prologue. Playtested, 0 errors.

What changed:
- Shared/ItemData.JournalPages — all 6 rewritten (Captain's Log I-VI: Departure / Descent /
  Contact / Retrieval / It Followed / The Truth). Coherent GDD arc: sealed orders -> below
  crush depth -> something deliberate resting on the trench floor -> cargo taken aboard ->
  it followed and crashed us to stop us surfacing -> return the cargo to the stern breach and
  it lets the living pass (seeds the_truth, warns against hubris). ~3-5 sentences each.
- Shared/Net — NEW S2C remote "JournalRead" {title,text,index}.
- Server/InventoryManager.onJournal — now fires JournalRead (full page to the reader) + a short
  "you find a page of the captain's log" notify, instead of cramming title+text into the
  one-line notify (which clipped at ~700px / 4s).
- Client/HUD — NEW journal reader: a worn serif "page" panel (own ScreenGui, DisplayOrder 60),
  wrapped text, fades in, auto-fades after a read time scaled to length (7-16s), or set down
  early by any key/click after a 1.2s grace. Non-blocking (the real-time horror keeps running).
- ReplicatedFirst/IntroScreen — expanded prologue: 5 staggered lines (sealed orders into a
  trench no chart admits / sent to bring something back, succeeded / it followed them down /
  hull broken on the seabed, water climbing / you're the last one breathing, it hears
  everything). Skippable after the first beat; hard 22s cap so a join can never hang on it.

Verified (run_test): new text loads (page1 "Captain's Log — I. Departure"; pages 270 / 375
chars), JournalRead created by Net.Init, the journal handler fires it cleanly, count 0->1, page
part destroyed. 0 errors at boot.

Notes for the team:
- CLIENT scripts changed (HUD, IntroScreen) -> need a fresh Stop->Play to reload. Server + Net
  reload on Play. NEEDS CTRL+S.
- The galley notice board + captain's-safe letter are separate minor lore (onNotice / onSafe) —
  left as-is for now; say if you want those rewritten in the same voice.


----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 31 — Reset Character = full restart too]

Type: Feature

Summary: Razvan: the in-experience "Reset Character" button should restart the whole game,
exactly like losing. Intercepted the reset so it runs the same full ResetRun instead of the
default kill+respawn (which kept the inventory + the explored world). Playtested, 0 errors.

What changed:
- Shared/Net — NEW C2S remote "RequestResetRun".
- Client/EndingClient — StarterGui:SetCore("ResetButtonCallback", bindable): the reset button
  now fades to black + fires RequestResetRun instead of the default reset (so it no longer just
  kills + respawns with everything intact). Retries the SetCore until CoreGui accepts it.
- Server/EndingManager — handles RequestResetRun -> EndingManager.ResetRun(player), with a 2s
  per-player debounce (lastReset) so it can't be spammed (ResetRun rebuilds the shared world).

Verified (automated run_test, player ALIVE / never lost): collect 3 items + the flashlight,
seal door 1-2, fire RequestResetRun. After: world back to 11 pickups / 6 journals, inventory
4/4 free, flashlight gone, door un-sealed. 0 errors.

Notes for the team:
- Reset is now a FULL restart (loses all progress) by design — it is no longer an "un-stick".
- The client change (EndingClient) needs a fresh Stop->Play to reload; the server + Net changes
  reload on Play. NEEDS CTRL+S to persist.


----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 30 — "Try Again" = true full restart]

Type: Fix / Feature

Summary: Razvan: losing to the creature + pressing "Try Again" only sent the player to
spawn and KEPT the inventory. Reworked the restart into a true fresh run. Playtested
end-to-end (creature path), 0 errors.

Diagnosis (tested, not guessed): the 4 inventory slots ALREADY cleared server-side
(ResetRun -> Inventory.ResetPlayer, confirmed via the real RequestRestart remote round-trip).
What ResetRun did NOT reset: the flashlight/battery (its slot lingered = the "kept item"),
oxygen, bulkhead doors (open/sealed), the captain-door/safe locks, and — because the baked
map makes MapBuilder.Build a no-op — every world Pickup/Journal the player had collected
(destroyed on pickup, never respawned, so a died-on run was unwinnable).

What changed:
- NEW Server/RunReset (ModuleScript) — at boot snapshots the pristine world: clones every
  "Pickup"/"Journal" into ServerStorage.__RunResetTemplates and records each BulkheadDoor's
  open/sealed/colour/prompt state + the captain-door/safe Locked state. RestoreWorld()
  (called by ResetRun) destroys all current world collectibles, re-clones the originals into
  their parents, re-closes/un-seals every door, and re-locks the captain door + safe.
  Idempotent (re-clones from the master each restart). Re-cloned prompts auto-reconnect via
  InteractionManager's Workspace.DescendantAdded hook.
- Server/Bootstrap — RunReset added to MANAGER_ORDER after InteractionManager, so the
  snapshot runs once after MapBuilder+Dress and before anything can be collected.
- Server/BatteryManager — NEW ResetPlayer(): drops flashlight ownership + charge and pushes
  a BatteryUpdate so the client hides the flashlight slot + kills the beam (player re-collects
  the torch in §1).
- Server/OxygenManager — NEW ResetPlayer(): refill + clear death flag + hide the meter now
  (CharacterAdded already did this on respawn; this makes it immediate).
- Server/EndingManager.ResetRun — rewritten: every step is pcall-guarded so a single failure
  can never strand the player holding their old inventory; now also calls RunReset.RestoreWorld
  + Battery/Oxygen ResetPlayer and clears the HasFlashlight/Hiding attributes. Dropped the dead
  MapBuilder.Build() call (no-op on the baked sub).

Verified (automated run_test): collect 2 pickups + 1 journal, grab the flashlight, seal door
1-2, unlock the captain door, then trigger taken -> ResetRun. AFTER: world back to 11 pickups
/ 6 journals, door un-sealed, captain re-locked, inventory 4/4 free, flashlight gone. Snapshot
= 17 templates. 0 errors at boot or restart.

Notes for the team:
- RunReset resets the SHARED world, so in multiplayer one player's Try Again would respawn
  items / reset doors for everyone (consistent with the existing global Flood/Power/Creature
  reset). Fine for the solo experience; revisit if co-op is ever added.
- Dropped items ARE cleared on restart (drops are tagged "Pickup"); a placed glow-stick's
  light is left to its Debris timer.
- All changes are server ModuleScripts — no client edits (the existing Inventory/Battery UI
  handlers already clear on the pushed updates). Reloads on Play. NEEDS CTRL+S to persist.


----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 29i — captain door art; notice board un-merged; galley chairs/sofa/table]

Type: Art / Fix

Summary: Razvan: (1) texture the captain's-room door; (2) bulletin board merges with the
wall — fix; (3) the rectangular shapes in room 3 (galley) -> chairs/sofa + table with chairs.
All in the Dress() pass. Played, 0 errors.

(1) Captain door (MapBuilder.dressCaptainDoor, finds Interactable kind=captain_door). Now a
heavy cabin bulkhead door: Metal reskin + riveted frame border, rivets, a porthole window
(steel ring + glass), a 4-spoke wheel handle, a RED (locked) keycard reader, and a CAPTAIN
nameplate (SurfaceGui). 20 DD_C greeble, CanCollide=false. (Caveat: onCaptainDoor only fades
the door body to 0.7 when unlocked; the greeble stays opaque — minor, left as-is.)

(2) Bulletin board merge fix (dressNotice, now takes cx). It sat at z=11.7, 0.1 off the +Z
wall (inner face z=12) = visually merged. Now repositioned to a STABLE z = cx-derived
(IW/2-1.1 -> z=10.9), pulled ~1 stud into the room, with a raised wooden frame border and 2
metal mounting brackets bridging back to the wall, so it clearly reads as a mounted board.

(3) Galley furniture (extended dressGalley). The two thin slab 'tables' (Table1/Table2) now
get 4 metal legs each + 4 chairs apiece (seat/back/2 leg-bars, facing the table) = 8 chairs.
Plus a worn 3-cushion sofa (base/back/2 arms/cushions) against the +Z wall with a low coffee
table + legs in front. ~52 new parts. (Counter left as the galley counter.)

Verified: playtest -> dressing applied -> all managers -> bootstrap complete, 0 errors.
NoticeBoard now z=10.9 (+frame/brackets); CaptainDoor 20 greeble; galley 8 chairs + sofa +
table legs + coffee table. Needs Ctrl+S (also regenerates from code each Play).

----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 29h — bunk beds; breach IS the wall (drift bug fixed); journals rested]

Type: Fix / Art

Summary: Razvan: (1) turn the wall "plates" into bunk beds; (2) breach is now BEHIND the
wall — make it BE the wall; (3) some journal pages float — rest them on something / the
ground (keep their location). All done in the Dress() pass. Played, 0 errors.

(2) BREACH DRIFT BUG fixed + made flush. Root cause: dressBreach computed
wallX = br.Position.X + 2 from the breach's OWN (already-moved) position, so every Dress()
shoved it +2 outward. After this session's many Dress runs it had drifted to x=425 — 8 studs
behind/outside the stern wall. Now wallX = cx + IL/2 + WT/2 (derived from section centre,
STABLE; verified no drift after running Dress twice). The membrane now spans the full wall
thickness (Size.X = WT) with its room face flush at the inner wall plane (x=416) and teeth
ringing the opening at that face -> it reads as the wall itself torn open, black ocean behind.

(1) Bunks -> beds (MapBuilder.dressBunks). The thin 6x0.5x3 "Bunk*" slabs (S1 x2 stacked,
S2 x3) now get: Fabric mattress reskin + a padded mattress pad, a pillow, a rumpled blanket,
steel frame rails on 4 sides, and corner posts. Posts run to the floor for lower/single bunks
and only down to the bed below for an upper bunk (detects a Bunk directly under it) -> proper
stacked bunk-bed frames in S1. ~55 greeble.

(3) Journals settled (MapBuilder.placeJournals, runs last). For each Journal page: raycast
down (excluding the page + water + breach), then rest it on the first surface hit
(surface.Y + 0.12). If that surface is the bare deck ("Floor"), drop a small WoodPlanks crate
(DD_JrRest_<name>) under it and sit the page on top (~y0.88). Results: J1/J3/J4 -> on a crate
on the floor; J2 -> on the bunk bedding; J5 -> on the safe; J6 -> on the radio console. XZ
location unchanged (only height), per Razvan. Idempotent: crates are DD_*, cleared+rebuilt
each run; page heights recompute from the stable surface below. NOTE: Dress runs ONCE at real
server start (the correct path); a back-to-back double Dress in testing can transiently skip a
crate, but single-run (production) is correct.

Verified: playtest -> "...+ lockers + vault + cargo + bunks/journals" -> all managers ->
bootstrap complete, 0 errors. Breach x=417 size.x=2 stable; 6 journals rested; bunks dressed.
Needs Ctrl+S (also regenerates from code each Play).

----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 29g — exterior passage -> sealed cargo crate]

Type: Art

Summary: Razvan: texture the aft ExteriorPassage (the "container near the torpedoes, left
of the entrance") into a sealed cargo crate. Done in the Dress() pass; prompts/endings
untouched. Played, 0 errors.

Context: the ExteriorPassage (S9, kind=exterior, at 372,3,-9) is the secret-ending choice
object ("the cargo") — gated by all 6 journals, then Return -> the_truth / Take -> hubris.
It was a plain dark cube, so it read as an unmarked container. Now it looks the part.

Crate dressing (MapBuilder.dressExterior, in Dress(), idempotent). Body -> WoodPlanks brown;
+23 DD_X greeble parented to the part: 2 horizontal steel wrap-bands, 4 vertical corner
brackets with rivets, a recessed front panel, a hasp + padlock + shackle, a neon seam sliver
with a faint sickly-cyan PointLight leaking from the seam, and a SurfaceGui stencil ("CARGO" +
red stripe + "DO NOT OPEN"). All CanCollide=false; ReturnPrompt + TakePrompt left intact (the
crate body keeps CanCollide so it's still approachable/interactable).

Verified: playtest -> "dressing applied to 9 sections + lockers + vault + cargo" -> all
managers -> bootstrap complete, 0 errors. 23 DD_X greeble + stencil + both prompts present.
Needs Ctrl+S (also regenerates from code each Play).

----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 29f — aft torpedoes modelled; torpedoes are decor (no open/code)]

Type: Art / Q&A

Summary: Razvan clarified the earlier "vault" question was about the TORPEDOES in the last
room (S9 aft torpedo), not the captain's safe. Modelled them as real torpedoes; answered the
"how to open / code" question. Played, 0 errors.

How they open (answer): they DON'T — the aft torpedoes are decoration (no prompt, no code).
The only interactables in S9 are HullBreach ("Swim out", the_deep ending) and ExteriorPassage
("Return/Take the cargo", secret endings). Offered to make a torpedo interactive if wanted
(lore reveal / hidden item) — not built yet, awaiting Razvan's call on what opening should do.

Torpedo art (MapBuilder.dressAft, in Dress()). Replaced the 2 plain DD_AftTube cylinders with
2 full torpedoes on steel cradles along the -Z wall, noses toward the stern: brass-steel body
(7 x 1.8 cyl), rounded warhead nose (Ball), yellow hazard band + red stripe near the nose, 4
cruciform tail fins, a propeller hub, and two cradle supports. 11 parts each / 22 total, all
DD_Torp* (idempotent), CanCollide=false.

Verified: playtest -> "dressing applied to 9 sections + lockers + vault" -> all managers ->
bootstrap complete, 0 errors. 22 DD_Torp parts in S9.
Needs Ctrl+S (also regenerates from code each Play).

----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 29e — vault (safe) dressing + open-mechanic clarification]

Type: Art / Q&A

Summary: Razvan: texture the "vault in the last room" + "how do I open it, need a code?"
Clarified location + mechanic, and dressed the safe as a round-door vault (code-driven).
Played, 0 errors.

Location note: the only safe/vault is the Wall Safe in Section 4 (officers/captain's
quarters), NOT the last room (S9). The captain's room is gated by the keycard door (keycard
from the sonar room), which is the real lock.

How it opens (answer): NO combination entry. onSafe (InventoryManager:270) just unlocks on
interact and returns lore — "The combination from the photographs works. Inside: a worn
wedding ring and a final letter." The "Enter Combination" prompt text + the captain's-room
photographs are narrative flavour; mechanically you walk up and press E. It grants no item
(pure lore container). If we want a real number puzzle later, add it in onSafe.

Vault dressing (MapBuilder.dressSafe, in the Dress() pass, idempotent). Body -> Metal, dark
steel (48,52,58), reflectance; + 17 DD_Sf greeble parented to the safe: raised door frame,
a circular vault door (cylinder), a 4-spoke wheel + hub, a combination dial + knob, 6 rim
bolts, and 2 side hinges. CanCollide=false. Derived from the safe's own position so it works
baked or procedural.

Verified: playtest -> "dressing applied to 9 sections + lockers + vault" -> all managers ->
bootstrap complete, 0 errors. Safe confirmed Metal + 17 greeble.
Needs Ctrl+S (also regenerates from code each Play).

----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 29d — steel-locker skin + hide-fade + linger 35->10s]

Type: Art / Tuning

Summary: Razvan: (1) re-skin the lockers to look like real lockers; (2) confirm the
"hide in a locker -> monster gives up after a few seconds" behaviour. Did both. Played, 0 errors.

(1) Steel-locker skin (MapBuilder.dressLockers, called from Dress() every server start).
For every HidingSpot: body -> DiamondPlate, grey-green (84,96,88), slight reflectance; plus
10 greeble parented to the locker itself (so the hide fade can reach them): a recessed door
panel, two louvre vent bands (6 slats), a vertical handle + latch, and a numbered plate
(SurfaceGui, 2-digit id from X). All CanCollide=false. Greeble named DD_Lk* so Dress's DD_
clear keeps it idempotent. NOTE: BrokenPanel (S1) is also a HidingSpot so it now reads as a
locker too — say if you want it left as a torn wall panel instead.

  Hide fade upgrade (CreatureManager.toggleHide): the new opaque door would re-introduce the
  black screen, so toggleHide now records EVERY BasePart on the locker (body + greeble) and
  fades them all to 0.7 while hiding, restoring exact originals on exit (was a single-part
  transparency). You climb inside and see out through the translucent door/vents.

(2) Confirmed + tuned. The behaviour already worked: on reaching your last sound while Hunting,
if no EXPOSED player is found (hiding[] players are skipped by the kill check) the creature
searches, then returns to its base state. Because someone is hiding nearby it uses
hideLingerSeconds. That was 35s (too long to hold still) -> set to 10s in CreatureData.
IMPORTANT nuance: moving the MOUSE while hiding fires "heartbeat" (intensity 2) -> ReportSound
at the locker -> re-targets the creature and resets the timer. So: hide + stay still ~10s ->
it leaves; twitch the mouse -> it stays. (searchSeconds=15 is the separate give-up when you
just broke line-of-sound without hiding.)

Verified: playtest -> "dressing applied to 9 sections + lockers" -> all managers -> bootstrap
complete, 0 errors. 3 lockers each have 10 greeble + number plate.
Couldn't eyeball first-person here (screen_capture blank) — confirm in-game the locker view is
clear while hiding. Needs Ctrl+S (decor/skin also regenerate from code each Play regardless).

----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 29c — real breach + inside-the-locker hide; water logic confirmed]

Type: Fix / Art

Summary: Razvan: (1) the aft breach floats in front of the wall — make it the actual
breach; (2) some lockers are buggy, check/fix all; (3) did the open-door water-leveling
logic persist? Answers: water logic is fully intact + live; fixed the breach to sit flush
in the wall opening; fixed the locker hide so you actually go inside. Playtested, 0 errors.

(1) Water leveling — PERSISTED & WORKING (no change needed). InteractionManager.setDoorOpen
sets door Open=true on use; FloodManager.step equalises every Open & not-Sealed BulkheadDoor
toward the mean of its two sections (EQUALIZE_RATE 1.5). Open a bulkhead -> the two rooms
level out. It's code, so it survived.

(2) Breach made real (MapBuilder.dressBreach, runs every server start). Was a 0.5-transparent
slab at x=415 — 2 studs IN FRONT of the stern wall plane (x=417), so it read as a floating
panel. Now: HullBreach is repositioned FLUSH into the actual stern-cap opening (x=417, size
1.2 x 7.4 x 13.6, dark glass trans 0.2), with a near-black DD_VoidBack just outboard (you see
only the deep, never the skybox), 16 jagged DD_Edge torn-metal teeth around the rectangular
rim, the blue breach light, and water spray/bubbles blowing inboard. Derived from br position
(wallX = br.X + 2) so it stays correct on baked + procedural.

(3) Locker hide fixed (CreatureManager.toggleHide). The bug: on hide the player was parked at
the locker MOUTH +0.3 — i.e. STANDING IN THE OPEN ROOM in front of the cabinet, facing away
from it (the old anti-black-screen hack from s22). Now they climb INSIDE (insideZ = front face
- 0.5), facing out, and the cabinet is set translucent (Transparency 0.55) while occupied so
the first-person camera sees OUT through the door instead of going black — restored on exit.
Facing is robust now (toRoom = sign of -Z; works for a locker on either long wall, not just -Z).
Also disable the locker's own ProximityPrompt while hiding (exit stays the deterministic E ->
ExitHide) to kill the double-trigger ambiguity. Applies to all 3 HidingSpots (S1 BrokenPanel,
S2 Locker2/2b).

Verified: playtested — baked map -> dressing applied to 9 sections -> all managers up ->
bootstrap complete, 0 errors. HullBreach confirmed at (417,4,5), 16 teeth, void back present.
NOTE: couldn't eyeball the first-person locker camera here (screen_capture is blank) — Razvan
should confirm in-game that hiding now puts you inside looking out (no black screen).

Needs Ctrl+S to persist the script edits + the Edit-mode breach reposition (decor still also
regenerates from code on every Play regardless).

----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 29b — bake ALL decor into MapBuilder (code-driven)]

Type: Fix / Art / Architecture

Summary: Continuation of s29. Razvan: "I saved every time, I don't get it" + "rebuild
ALL that's missing and bake it into MapBuilder." Re-diagnosed (his saves were fine) and
moved ALL decorative dressing out of hand-baked Workspace instances into code, so it
regenerates every server start and can never be lost again.

Corrected root cause (the real "why"): NOT a missing Ctrl+S. The tell is what survived —
every Script, the MaterialVariants, and the s9 particles persisted, but every baked DECOR
part from s15 on did not. That split = the decor was created in PLAY (Server) DataModel
sessions ("verified by automated playtest" all over the log). Instances made during Play
live only in the runtime DataModel and are discarded on Stop — they were never in the
Edit place, so saving Edit had nothing to save. Team Create live session is also active.

The fix (code-driven, idempotent dressing):
- MapBuilder: NEW MapBuilder.Dress() + wired into MapBuilder.Start() AFTER Build(). Build()
  still early-returns on the baked Submarine, so Dress() is a SEPARATE pass that runs every
  start (baked OR procedural). It clears all "DD_*" descendants then rebuilds, driven by the
  same SectionData the baked map uses (positions line up). 197 instances / 9 sections.
- Restored content: per-section industrial dressing (2 ceiling pipe runs, conduit bundles,
  2 ring frames, valve+wheel, gauge+neon LED); console glass screens+LEDs (Helm/Nav/Ballast/
  Sonar/Radio); generator greeble (5 vents, exhaust stack+ceiling pipe, 2 coolant pipes,
  yellow hazard trim, lit DD_GPanel SurfaceGui, DD_Steam/DD_Sparks); hull-breach art
  (DD_VoidBack, 12 DD_Edge teeth, blue DD_BreachLightAnchor, DD_Spray/DD_Bubbles); galley
  dishes + DD_Poster notice; berthing belongings; officers desk effects + lamp light; S6
  sonar/radio partition + 2nd EmergencyLight; aft torpedo tubes/debris/hanging panel;
  conning-tower periscope eyepiece/console/screen/seat.
- IntroScreen (loading card) stays as the real LocalScript rebuilt earlier in s29 (client
  scripts persist normally — that one was genuinely just unsaved).

Verified: playtested. "using baked Submarine" -> "dressing applied to 9 sections" ->
all managers up -> Server bootstrap complete. 0 errors (only the usual DataStore
StudioAccessToApisNotAllowed). PowerManager picked up the extra tagged EmergencyLight fine.

Notes for the team:
- All decor is CanCollide=false; idempotent clear-and-rebuild means no duplication even
  though the Edit place now also contains a copy (created so the sub looks dressed while
  editing). To force a clean rebuild any time: delete DD_Dressing folders / DD_* parts; or
  just Play. To re-skin, edit the dress* helpers in MapBuilder.
- This finally decouples decor from the save/Play boundary: it's in code now. Future art
  should go in Dress(), not hand-placed in Workspace, or it can be lost the same way.
- Saving is still nice (keeps the Edit-mode preview + IntroScreen) but no longer REQUIRED
  for the dressing to exist in-game.

----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 29 — re-applied lost baked decor (CTRL+S!)]

Type: Fix / Art

Summary: Razvan: "almost everything from last time isn't saved — generator textures,
loading screen, maybe more." Diagnosed: the place file was last SAVED around session
~9-14, so every baked instance added via MCP after that (which only lives in the
running DataModel until Ctrl+S) was lost when Studio reloaded. Re-applied the two named
items. NOT YET SAVED — Razvan must Ctrl+S or this is lost again.

Root cause (the "why"): MCP edits the live DataModel only; instances become part of the
.rbxl on Ctrl+S. Survivors all predate ~s9 (MaterialVariants in MaterialService,
generator DD_Steam/DD_Sparks, breach DD_Spray/DD_Bubbles, all scripts). Everything
baked from ~s15 on was never persisted.

What I rebuilt:
- ReplicatedFirst/IntroScreen (LocalScript) — the loading/intro card from s24:
  RemoveDefaultLoadingScreen, black DisplayOrder-1000 ScreenGui, two fading Merriweather
  lines ("You wake in the dark..." / "The crew is gone..."), holds until IsLoaded +
  character HRP + 3 render frames + MIN_SHOW(5s), then fades + destroys.
- Generator (Section_8) greeble from s18 — 14 DD_ parts re-added (kept the existing
  deepdescent_hull_rust MaterialVariant + DD_Steam/DD_Sparks): 5 ribbed vents, vertical
  exhaust stack + horizontal ceiling pipe, 2 side coolant pipes, 4 yellow hazard base
  trims, and DD_Panel — a lit SurfaceGui ("MAIN GENERATOR" amber title, "OFFLINE -
  STANDBY", 2 needle gauges, G/A/R LEDs). CanCollide=false; prompt/particles untouched.

STILL MISSING (same root cause, not yet rebuilt — awaiting Razvan's go):
- s15 ~252-part DD_Detail/DD_Props room dressing (pipes, conduits, gauges, room props).
- s18 Galley NoticeBoard DD_Poster; HullBreach torn-metal art (DD_Edge/DD_VoidBack/
  DD_BreachLight); s23 Periscope dressing.

Notes for the team:
- *** CTRL+S NOW *** — both rebuilds are baked instances; unsaved = gone on next reload.
- Clean boot, 0 errors (only the usual StudioAccessToApisNotAllowed DataStore warning).
- Long-term fix to stop re-losing this: bake the decor into MapBuilder/code so it
  regenerates, OR just remember to save every session.

----------------------------------------------------------------------------
2026-06-30 — Claude (Claude Code)  [session 28 — creature shape + more aggressive + close-range catch]

Type: Art / Tuning / Feature

Summary: Razvan: give the creature a shape, make it more aggressive once the
generator's on, and stop the player slipping right past it (even crouched). Built
a deep-sea-creature silhouette, bumped alerted/dormant sensing, and added an
always-on close-range catch. Verified (30 shape parts, dormant->hunting on close
movement), 0 errors.

What changed:
- Server/CreatureManager.spawnCreature — the box is now a strange anglerfish-like
  thing: bulbous head + snout, a black maw with ragged teeth, a glowing green lure
  on a drooping stalk (with a faint light), side gill-fins, dorsal spines, and 6
  splayed tentacles — ~30 parts welded to the (now murkier, 0.5-transparent) body,
  all dark so it stays a silhouette. Glowing red eyes + the dim red proximity glow
  kept. Faces -Z (its travel direction).
- Shared/CreatureData tuning (more sensitive / more aggressive):
  * dormant detectionRadius 30 -> 40.
  * alerted (after main power): speed 14 -> 18, detectionRadius 60 -> 95,
    detectionSections 2 -> 3. Restoring the generator now clearly ramps the threat.
  * hunting speed 22 -> 24.
  * NEW CloseSenseRadius = 13.
- Server/CreatureManager.step — NEW close-range sensing: each tick, any non-hiding
  player who MOVED since last tick AND is within CloseSenseRadius of the creature is
  instantly detected (-> Hunting), regardless of crouch. Crouch still hides you at a
  distance; standing dead-still right next to it is still safe (no position change).
  Tracks lastPlayerPos (cleared on PlayerRemoving).

Notes for the team:
- Tunables: CreatureData (speeds, radii, CloseSenseRadius); the shape is procedural
  in spawnCreature (swap in an imported mesh later if wanted — set it as the Body or
  weld it the same way).
- Creature still LIVE. Needs Ctrl+S; server scripts reload on Play.
- Shape parts are welded to the anchored body (it's moved by CFrame in step) so they
  follow; CastShadow only on head+body for budget.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 27 — crouch feedback (felt broken: no visual)]

Type: Fix / UX

Summary: Razvan: "crouch doesn't work." SoundProducer (enabled, source intact)
already slowed the player to CrouchSpeed and suppressed footstep SoundEvents while
crouching — but it gave ZERO visual feedback, so it felt dead. Added a first-person
camera dip on crouch + broadened the binds. Clean boot, 0 errors.

Diagnostic note: a server run_test read Humanoid.WalkSpeed = 16 (default) and
"SoundProducer present=false" — BOTH are false negatives. Client-set WalkSpeed does
not replicate to the server, and client LocalScripts under PlayerScripts aren't
visible to the server. So that did NOT prove SoundProducer was dead; the real issue
was lack of feedback. (Can't drive client key input via MCP, so this is the
high-probability fix; the camera dip also doubles as a "did the key register?" tell.)

What changed:
- Client/SoundProducer:
  * Movement block — when crouching, smoothly lerp Humanoid.CameraOffset to
    (0,-1.8,0) so the view visibly ducks; resets to 0 when standing. (Speed ->
    CrouchSpeed and footstep-silence behaviour unchanged — they already worked.)
  * Binds — crouch now LeftControl / RightControl / C; run now Left/Right Shift
    (via isCrouchKey helper).

Notes for the team:
- If crouch STILL feels wrong: check whether the camera dips when pressing Ctrl/C.
  If it dips -> input + crouch are working (it's a feel/tuning thing: CrouchSpeed=7
  in GameConfig). If it does NOT dip -> input isn't reaching the script (deeper
  issue, e.g. another script consuming the key) and we debug from there.
- Crouch stealth is real: crouching emits no walk/run SoundEvent, so the creature
  (which is blind/sound-only) can't hear you crouch-walking.
- Client script — needs a fresh Stop->Play; Ctrl+S to persist.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 26 — creature is perceptible: rising audio + glowing eyes]

Type: Art / Audio / Tuning

Summary: Razvan: the creature was "unannounced" — invisible and silent. Made it
telegraph itself: creature audio now RISES with proximity, and it has glowing
eyes + a faint red proximity glow (still a silhouette, not a full reveal).

What changed:
- Client/AudioManager — creature 3-tier audio was flat on/off at low volume; now
  scales with closeness: rumble clamp((160-d)/160)*0.45, drag clamp((80-d)/80)*0.7,
  breathing clamp((32-d)/32)*1.0 (faster ramp). You hear a distant rumble, then a
  wet drag as it nears, then breathing when it's almost on you. (Hunting still does
  the 2s-silence -> charge sting.)
- Server/CreatureManager.spawnCreature — body Transparency 0.35 -> 0.25; added two
  Neon red "Eye" balls welded to the body front (-Z = travel direction) and a dim
  short-range red "EyeGlow" PointLight (Brightness 0.5 / Range 9 / no shadows). The
  eyes read as two red dots down a dark corridor; the glow only lights right around
  it when very close. Verified: spawn has 2 neon eyes + EyeGlow, 0 errors.

Notes for the team:
- Tunables: audio falloff distances/volumes in AudioManager; eye color/size +
  EyeGlow brightness/range in spawnCreature; per-state speed + detection radii in
  Shared/CreatureData.
- Creature is still LIVE (FreezeCreature=false).
- Needs Ctrl+S to persist; client audio + creature respawn need a fresh Play.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 25 — captain door + safe art, CREATURE LIVE, escape/lose tests]

Type: Art / Tuning / Test

Summary: Dressed the captain's-quarters door + the safe, TURNED THE CREATURE ON
(FreezeCreature=false), and ran two scripted end-to-end playtests: one good ending
(escape pod) and one bad ending (creature kill). Both passed, 0 errors.

What changed:
- Workspace.Submarine.Section_4.CaptainDoor (baked) — was a plain blue slab. Now
  Metal steel-grey + 12 DD_ parts: a brass hatch wheel + hub, a keycard reader with
  a red neon LED, a glass porthole + rim, four corner rivets, and a "CAPTAIN"
  SurfaceGui nameplate on the +Z (approach) face.
- Workspace.Submarine.Section_4.Safe (baked) — was a plain cube. Now Metal + 9 DD_
  parts: a recessed door panel, a combination dial with a red index pip, a spoke
  handle + hub, two hinges, and a brass nameplate (all on the +Z face).
- Shared/GameConfig.FreezeCreature  true -> FALSE. The creature now patrols
  (dormant), alerts on main power, hunts on sound, and kills. (Debug still true.)

Tests (automated run_test, monster live):
- ESCAPE: added 3 pod_component -> InteractionManager pod_panel handler ->
  EndingManager fired "escape_pod"; DataManager recorded escape_pod=true,
  completed=true. 0 errors.
- LOSE: confirmed creature state=dormant at boot (unfrozen), moved it onto the
  player + ReportSound("run") + SetState("hunting"); its own step loop ran the kill
  check -> EndingManager fired "taken"; recorded taken=true. 0 errors.

Notes for the team:
- CREATURE IS NOW LIVE for normal play. (To re-freeze for building, set
  GameConfig.FreezeCreature = true.)
- Tests drove the real managers/handlers (not a hand-walked playthrough) — they
  prove the ending pipelines + the live AI kill path, not navigation/timing feel.
- Needs Ctrl+S (baked door/safe art). GameConfig change reloads on Play.
- BAKED caveat: door/safe dressing is on the baked instances; MapBuilder unchanged.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 24 — intro title card + per-room generator lights]

Type: Feature / Fix

Summary: (1) Added a black two-line story title card shown before the world is
visible, held until loaded + character spawned + a min readable time, then fades
(hides the first-frame render/shader pop-in). (2) The generator lighting still
left rooms dark (the MainLight spots are narrow); added a dim PointLight in EVERY
room that turns on with the generator so you can see a little without the torch.
Verified: generator start lit 10/10 room fixtures; clean boot, 0 errors.

What changed:
- NEW ReplicatedFirst/IntroScreen (LocalScript) — RemoveDefaultLoadingScreen, then
  a full black ScreenGui (DisplayOrder 1000) with two fading Merriweather lines:
  "You wake in the dark, ankle-deep in rising water." /
  "The crew is gone. Something came aboard with you."
  Holds until game:IsLoaded() + the character has a HumanoidRootPart + 3 render
  frames + MIN_SHOW (5s), then fades out and destroys itself. (CharacterAutoLoads
  is true and MenuUI is only an L-toggled overlay, so the character-wait can't
  deadlock.)
- Server/PowerManager — new setMainGlow(on): ensures a soft white PointLight
  ("MainGlow", Color 225,232,244 / Brightness 2.0 / Range 30 / Shadows off) on
  each EmergencyLight fixture (one per room) and toggles it. Called setMainGlow(true)
  in startGenerator (with setMainLights/power_surge) and setMainGlow(false) in Reset.
  This is the real "generator on = rooms are dimly lit" layer; the narrow MainLight
  spots + steady-dim rework (s23) remain on top.

Notes for the team:
- Edit the two story lines in ReplicatedFirst/IntroScreen; MIN_SHOW tunes how long
  the card stays. Story text is a placeholder — swap freely.
- MainGlow lives on the baked EmergencyLight fixtures at runtime (created on first
  generator start); brightness/range tunable in setMainGlow. 10 fixtures = 10 rooms
  (8 linear sections + captain room; tower has its own fixture too if tagged).
- Server scripts reload on Play; the intro is a client script (re-Play to see it).
  Needs Ctrl+S to persist (the IntroScreen instance + script edits).

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 23 — flood equalises thru open doors, generator dim lights, periscope art]

Type: Feature / Fix / Art

Summary: (1) Water levels now equalise between rooms connected by an OPEN
(unsealed) bulkhead door, so an open doorway no longer shows two different water
heights. (2) Reworked the main-power lighting: was a harsh constant strobe; now a
dim, clean, mostly-steady cool-white work light. (3) Dressed the periscope.
Clean boot, 0 errors; equalisation verified (diff 60 -> 0 open, stays 60 closed).

What changed:
- Server/FloodManager.step — after the per-section rise, loop BulkheadDoors; for
  each with Open=true and not Sealed, move both sections' levels toward their mean
  (EQUALIZE_RATE 1.5 -> ~level in <1s). Closed/sealed doors keep rooms independent
  (unchanged), so sealing still isolates flooding for the Sealed-In ending.
- Server/PowerManager — main-power lights are the "generator on" glow now:
  * setMainLights(on) -> steady dim cool white (Color 208,222,235, Brightness 1.5,
    BaseBrightness attr) instead of flat 2.2 + strobe.
  * flickerLight() -> rewritten: long steady stretches (4-11s) with an occasional
    brief subtle dip, reads as a settled fluorescent — NOT the red emergency strobe.
  (Emergency red PointLights + their flicker are unchanged; this is the separate
  white corridor layer that comes on with the generator.)
- Workspace.Submarine.Section_7.Periscope (baked) — was a plain box. Reskinned
  DiamondPlate + 11 DD_ parts: prism head with a glass viewport facing the hull,
  3 shaft bands, an eyepiece + dark glass lens facing the operator (+Z), two angled
  grip handles, and a base collar.

Notes for the team:
- Needs Ctrl+S (baked periscope). Server scripts reload on Play.
- Flood equalise is gradual (flows over a few ticks), not instant — looks natural.
  Tune EQUALIZE_RATE in FloodManager if you want faster/slower flow.
- Main-light brightness/color are tunable in setMainLights; the steady-vs-flicker
  feel is in flickerLight.
- BAKED caveat: periscope dressing is on the baked instance; MapBuilder unchanged.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 22 — console handlers, locker black-screen fix, breach solid]

Type: Fix / Feature

Summary: (1) "(System arrives in a later phase.)" was the dev placeholder shown
for any Interactable whose Kind had no handler — 4 objects hit it (notice,
periscope, sonar, ladder); gave them real behavior + replaced the message.
(2) Lockers still broke: my s21 anchor parked the player at the CENTRE of the
opaque cabinet -> first-person camera inside an opaque box = black/broken view.
Now seated at the locker MOUTH facing the room. (3) Breach was walk-through;
made it solid so the only way out is the "Swim out" prompt. Clean boot, 0 errors.

What changed:
- Server/InteractionManager — replaced the dev-placeholder fallback with a plain
  diegetic line, and registered 4 built-in handlers (set in Start):
  * notice    -> flavor read of the mess notices.
  * periscope -> GDD black-ocean / distant-lights flavor.
  * sonar     -> dead without main power; with it, reports the creature's rough
                 distance + fore/aft bearing (real tracking, per GDD 4.1/5.2).
  * ladder    -> climbs the player UP to the conning-tower floor (224,20.5,0) and
                 back DOWN to the control room (toggle by height). The tower was
                 otherwise unreachable.
- Server/CreatureManager.toggleHide — hide position fix. Was locker CENTRE (inside
  the opaque part). Now: mouthZ = locker front (+Z) + 0.3; CFrame.lookAt facing the
  room (+Z); still Anchored. Camera looks OUT, body tucked back, no physics eject,
  no black screen. Applies to all 3 hiding spots. Exit unchanged (ExitHide/E).
- Workspace.Submarine.Section_9.HullBreach (baked) — CanCollide = true. You can no
  longer walk into the abyss; the [E] "Swim out" prompt (the_deep ending) is the
  only way through. (Teeth stay non-collidable; the solid 2x8x14 membrane fills the
  hole.)

Notes for the team:
- Needs Ctrl+S (baked breach collision). Server-script changes reload on Play;
  the locker change is server-side (CreatureManager) so just re-Play.
- Lockers face +Z in every section (they sit on the -Z wall) — the mouth-facing
  math assumes that. If a future locker faces another way, pass its facing.
- Sonar bearing is fore/aft only (sub is a straight X-axis hull) — good enough; a
  full compass would need a 2D layout.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 21 — breathing windows, locker eject fix, breach aligned]

Type: Fix / Audio / Tuning

Summary: Three Razvan fixes. (1) Heavy breathing was a constant loop — now it
only plays for 5s at spawn + a 2s gasp after being submerged >4s. (2) Room-2
lockers ejected the player out behind them — anchored the player while hiding
(all 3 hiding spots fixed). (3) The aft breach floated in front of the wall —
moved + resized it to fill the actual stern hole. Heartbeat-while-hiding kept
(Razvan likes it). Clean boot, 0 errors.

What changed:
- Client/AudioManager — breathing rework. breathCalm (the heavy/"calm" loop) was
  always on at 0.3; now gated by a window: breatheUntil = spawn+5s, and a fresh
  2s window whenever player:GetAttribute("Submerged") has been true >4s (tracked
  per dive). Plays at 0.45, faster ramp. Creature-proximity breathFast/breathPanic
  and the hiding heartbeat are UNCHANGED.
- Client/WaterRenderer — now sets player attribute "Submerged" each frame (it
  already computed head-below-surface for the blur/overlay); AudioManager reads it.
  Also sets Submerged=false on the early-outs (no head / no section).
- Server/CreatureManager.toggleHide — the hide used CanCollide=false + teleport but
  NOT anchored, so the player capsule (overlapping the rear wall) got physics-shoved
  out behind the locker. Now: zero velocity, teleport to the locker CENTRE
  (locker.Position, was a hardcoded y=3), and hrp.Anchored = true; exit sets
  Anchored=false then restores. Safe now that ExitHide (E) is the exit path (s13),
  not the in-locker prompt. Fixes all 3 HidingSpots (S1 BrokenPanel, S2 Locker2/2b
  — identical 3x6x2.5 boxes ~0.75 off the rear wall).
- Workspace.Submarine.Section_9.HullBreach (baked) — was (415,6,6) size(2,8,10),
  floating ~2 studs in front of the stern wall and too high. The real opening (the
  uncovered gap: SternCapL covers z[-12,-2], SternCapTop covers y[8,16]) is
  y[0,8]/z[-2,12] at x~417. Moved breach to (417,4,5) size (2,8,14) so it fills the
  hole; rebuilt the DD_ torn-metal teeth/void/cold-light around the real rim. The
  BreachPrompt ("the_deep" escape) moved with it onto the actual hole.

Notes for the team:
- Needs Ctrl+S (baked breach move + DD_ children). Client scripts (breathing,
  Submerged attr) need a fresh Stop->Play.
- BAKED caveat unchanged: MapBuilder still builds the old breach position; this
  alignment is on the baked instance only.
- "Submerged" is a client-set player attribute (local only) — fine for the
  local-audio use; don't rely on it server-side.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 20 — dropped items vanished -> now physical]

Type: Fix

Summary: Razvan: dropped items disappeared. The drop branch only nil'd the slot
and never spawned anything. Now it drops a real, re-collectable pickup at the
player's feet.

What changed:
- Server/InventoryManager.useSlot (action=="drop") — builds a world pickup via
  ItemModels.BuildPickup(entry.id, hrp.CFrame * CFrame.new(0,-1.5,-2)) (at the
  player's feet, just ahead), names it Pickup_<id>, sets ItemId attr, tags it
  "Pickup", adds a [E] "Take" ProximityPrompt (dist = GameConfig.InteractDistance),
  parents to Workspace. InteractionManager's existing pickup handler re-collects
  it. Added CollectionService + Workspace requires to the module.
- Verified: InventoryManager requires clean; BuildPickup+tag+prompt path runs with
  0 errors (re-collectable via the standard onPickup flow). Clean boot.

Notes for the team:
- Flashlight can't hit this path (it's the dedicated slot, not one of the 4).
- Dropped pickups are Anchored (like all world items), so they hang where dropped
  even over water — consistent with the rest of the pickups.
- BAKED/regen caveat doesn't apply (pure runtime spawn). Needs Ctrl+S for the
  script edit; client needs no change (Q-drop keybind already shipped s18).

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 19 — GDD audit + AUDIO implemented]

Type: Audio / Feature / Review

Summary: Audited the build against the GDD (everything core is implemented), then
filled the #1 gap: AUDIO. Sourced 19 free Creator Store sounds (mostly Roblox's
ProSoundEffects library), wired the IDs, and added the missing one-shot triggers.
All 19 verified loadable (ContentProvider preload: 19/19 OK, 0 fail); clean boot.

KEY DISCOVERY: I can self-source audio. The Roblox_Studio search_asset tool
returns free Creator Store Audio (assetType=Audio, priceFilter=free) — these load
+ play in this place with no manual upload. No audio files needed from Razvan.

What changed:
- Shared/SoundData.Ids — all 19 placeholders (rbxassetid://0) replaced with real
  free asset ids (see the module for the per-sound mapping + source notes).
- Server one-shot SoundCue triggers (SoundCue was declared but never fired):
  * InteractionManager.handleDoor -> "door_metal" on every door open/close.
  * CreatureManager SoundEvent handler -> "splash" when a player enters water
    (footsteps stay silent: no asset + too noisy).
  * PowerManager.startGenerator -> "power_surge" the instant main power lights up
    (generator_start + generator_hum were ALREADY wired here, positional).
  * PolishManager -> new startAmbientAudio(): random distant "pipe_hiss"/
    "structural_groan" from a random lit fixture every ~7-18s, "electrical_spark"
    on each spark burst, and "sonar_ping" from the sonar console while main power
    is on. (Added Net + serverFolder requires to PolishManager.)
- Already-working (no change, just needed ids): AudioManager loops hull_groan,
  water_rushing(∝flood), breathing calm/fast/panic, heartbeat, creature
  rumble/drag/breath, and the hunting "2s silence -> creature_charge" sting.

GDD AUDIT verdict — implemented + matches the doc:
  9 sections + conning tower (baked); Flooding (FloodManager); 3 power circuits
  (PowerManager); creature 3-state AI + hiding (CreatureManager); 4-slot inventory
  + dedicated flashlight (Inventory/Battery); all items; endings 6+2 secret (+the_deep
  from s18); minimal HUD; first-person lock; Future/Realistic lighting + Atmosphere
  + Bloom + DepthOfField + SunRays; DataStore endings (DataManager). AUDIO now done.

Remaining gaps / launch TODO (NOT bugs):
  1. GameConfig.FreezeCreature = true and Debug = true — TEST AIDS still on. Flip
     both to false before a real creature/launch pass (creature won't move/kill
     while frozen).
  2. MonetizationData ids all 0 — need real game-pass/dev-product ids from Creator Hub.
  3. Lighting has no ColorCorrectionEffect (GDD 7.3 wants slight blue tint / reduced
     saturation) — the only missing post-FX. Easy add if wanted.
  4. Art is baked greybox + dressing; MapBuilder/ItemModels NOT synced (regen caveat).
     AI PBR MaterialVariants still absent (built-in materials only).
  5. Sonar is audio-only (periodic ping) — actual creature-tracking gameplay not built.
  6. Audio is functional/atmospheric, not hand-mixed. Swap any SoundData.Ids entry
     for a hero sound later; per-sound volumes live in AudioManager / the cue calls.

Notes for the team:
- Needs Ctrl+S (script edits persist with the place). Client audio needs a fresh
  Stop->Play. Sounds play from the live/published client too (assets are free CC).

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 18 — galley/generator art, drop key, breach + new ending]

Type: Art / Fix / Feature

Summary: Razvan fixes across two passes: (1) galley notice board + journal page,
(2) engine-room generator, (3) inventory drop, (4) the aft hull breach art, and
(5) a NEW breach-escape ending. All baked-instance + script work; clean boot,
0 errors (automated run_test passed).

What changed:
- Galley NoticeBoard (baked) — was a blank grey metal slab. Added DD_Poster
  SurfaceGui on its Front face: a corkboard "MESS HALL - DAILY NOTICES" poster
  (header, rationing/duty lines, red CLASSIFIED stamp, 4 tacks). LightInfluence
  0.15 so it reads in the dark.
- Journal_3 (the "note") — its interactive root (with the [E] Read prompt) was
  STRANDED at x~105 while the visible paper sat across the room at (128,-9), so
  walking up to the paper did nothing. Re-pinned root + all 5 child parts
  (Sheet1/2, Ink1-3) flush onto the notice-board face at ~(118.5, 5, 11.45);
  Read prompt (handler already in InventoryManager) now co-located. ObjectText
  "Captain's Page".
- Generator (Section_8, baked) — was a plain box with only particles. Now
  DiamondPlate + slight reflectance and 13 DD_ greeble: 5 ribbed vents, top
  exhaust stack + ceiling pipe, 2 side coolant pipes, yellow hazard base trim,
  and a front control panel (DD_Panel) with a lit SurfaceGui (amber "MAIN
  GENERATOR", "OFFLINE - STANDBY", 2 needle gauges, G/A/R indicator LEDs). All
  DD_ decor CanCollide=false; generator interaction prompt untouched.
- Inventory DROP fix — Client/InventoryUI: right-click drop was wired but
  UNREACHABLE in locked first-person (cursor pinned to center; no drop keybind).
  Added Q = drop selected slot (fires UseItem(slot,"drop"), server already
  handles it). Hint text -> "1-4 select  ·  E use  ·  Q drop". Right-click kept
  for free-cursor devices.
- Hull breach art (Section_9 HullBreach, baked) — was a flat semi-transparent
  metal slab. Now Glass/dark, with a DD_VoidBack "deep" plane behind, 30 DD_Edge
  torn-metal teeth + 2 peeled plates around the rim, a cold blue DD_BreachLight,
  and beefed water FX (DD_Spray/DD_Bubbles tuned to flow inward, new DD_Mist).
- NEW ENDING "the_deep" ("The Deep Took You", category BAD) — Razvan asked for
  an escape at the breach; per his call it's a GRIM death (no surviving crush
  depth), available any time. Added to Shared/EndingData (Endings + Order).
  Server/EndingManager: onBreach() -> notify + Trigger("the_deep"); registered
  Interaction handler "breach". HullBreach tagged Interactable + Kind="breach"
  with a BreachPrompt ([E] "Swim out", HoldDuration 1.2 so it can't fire by
  accident, dist 9).

Notes for the team:
- BAKED ONLY (same standing caveat): MapBuilder/ItemModels were NOT updated, so a
  from-scratch regen loses the poster, journal pin, generator/breach dressing,
  and the breach prompt/tag. The ENDING DATA + handler ARE in code (persist).
  Port the breach prompt+tag+Kind into MapBuilder if regen is ever re-enabled.
- Script edits done on the LIVE place via MCP (disk tree may still be stale per
  session 7 note). Needs Ctrl+S to persist baked instances; client script change
  (Q drop) needs a fresh Stop->Play to reload.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 17 — PARTIAL REVERT found; lights restored]

Type: Fix / Incident

Summary: Razvan: "why isn't the red light flickering anymore?" Investigation found a
PARTIAL REVERT of the baked Workspace: session 14 + 15 BAKED changes were rolled back,
while session 16 survived. Scripts (PowerManager flicker, etc.) were NOT affected.

What was lost (reverted to pre-session-14 state):
- Emergency lights back to Brightness 0.6 / Range 15 / BaseBrightness 0.6 (the dim
  session-4 values). The flicker code still ran, but around 0.6 with a 15-stud reach
  it's invisible against the dark -> looked like "no flicker."
- S6 partition + its 2nd emergency fixture (count 11 -> 10).
- ALL session-15 dressing (pipes/frames/valves/gauges/console screens) and props
  (galley food, tower cockpit, aft debris, berthing/officer items). DD_ parts ~343 -> 91
  (the 91 = session-16 bed/locker/tube details only).

What survived: session 16 (bunks->beds, metal lockers, fixed torpedo tubes, de-plastic
items) and all script changes.

Fix so far: re-set all 10 emergency fixtures to Brightness 1.6 / Range 34 /
BaseBrightness 1.6. Verified by playtest: base 1.6, flicker swings 0.44 -> 2.81 (bright
+ visible). Still TODO (pending Razvan): re-apply the session-15 dressing + props +
the S6 two-room split.

LIKELY CAUSE + PREVENTION: a reload / Team-Create sync / undo dropped un-persisted edit
changes. The selective survival (16 yes, 14-15 no) points to a sync/restore, not a
linear undo. ACTION: Ctrl+S immediately after any art change; if reverts keep happening
we have a Team Create persistence issue to chase.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 16 — de-plastic + bunks/lockers/tubes remodel]

Type: Art

Summary: Razvan flagged: items looked plastic; bunks didn't look like beds; lockers
looked like wood; S1 torpedo tubes looked plastic. Fixed all on the baked Workspace.
(Hull stays rectangular - no cylinders, confirmed.)

What changed (baked):
- Bunks -> beds: the 5 flat WoodPlanks slabs are now dark metal bed frames with a
  Fabric mattress + pillow + blanket + head/foot rails (DD_* children on each Bunk).
- Hiding spots -> metal lockers: Locker2 / Locker2b reskinned WoodPlanks -> DiamondPlate
  steel-green with two doors, handles, louvre vents, and a label plate. BrokenPanel
  (the S1 hide spot) -> CorrodedMetal with a bent flap (a battered hull panel, not
  wood). Tag / prompt / hide logic untouched (verified: 3 hiding spots all keep their
  ProximityPrompt and still work).
- S1 torpedo tubes: were Metal but oriented vertical (0,0,90) so they read as smooth
  pillars. Re-laid horizontal (axis X), DiamondPlate, each with a round near-black
  bore + rim ring + 6 hatch bolts - they read as torpedo-tube openings now.
- De-plastic items: 66 pickup/item parts switched off Plastic/SmoothPlastic -> Metal
  (glow stick -> Neon; any glass/led parts -> Glass/Neon). Submarine Plastic 23 -> 7
  (the 7 left are paper journals + the invisible spawn); SmoothPlastic 51 -> 38
  (journal sheets/ink, cloth props, water planes). Metal 83 -> 181. Only 3 WoodPlanks
  parts remain (tables/desk - intentionally waterlogged wood).
- Verified by playtest: clean boot, 0 errors; 3 hiding spots + 11 pickups all keep
  their prompts. Eyeballed S1 (tubes + escape pod) and S2 (a bed + a metal locker) via
  Edit-mode screenshots - all read correctly.

Notes for the team:
- BAKED ONLY: ItemModels (builds pickups) STILL emits Plastic, and MapBuilder still
  builds the old flat bunks / wood lockers / vertical tubes - so a from-scratch regen
  reverts these. The fixes live on the baked instances + their DD_* children. Port
  into ItemModels/MapBuilder if procedural regen is ever re-enabled.
- Decorative detail is CanCollide=false; locker/bunk/tube bodies keep original
  collision. Needs Ctrl+S to persist.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 15 — realism pass: materials + GDD room props]

Type: Art

Summary: Per Razvan + the GDD (section-4 room list, section-7.3 visual style), made
the rooms match the document and look more realistic. Kept the box shape (Razvan's
call: "textures + props only," NOT a cylinder rebuild). All on the BAKED
Workspace.Submarine (~252 new parts in per-section DD_Detail / DD_Props folders).

What changed:
- Material polish: ceilings -> CorrodedMetal (dark); WoodPlanks props darkened to a
  waterlogged tone. (Walls already CorrodedMetal, floors DiamondPlate grating,
  consoles Metal from session 9.) HEADS-UP: the session-9 AI MaterialVariants
  (deepdescent_hull_rust / floor_grate / console) are NO LONGER in MaterialService;
  parts still reference the names but fall back to the base material. I did not
  regenerate them (can't make AI PBR / can't invent texture asset IDs) — the built-in
  materials carry the realistic look.
- Industrial dressing, all 8 linear sections (DD_Detail): bow->stern ceiling pipes,
  low conduit bundles, ring frames (ceiling beam + wall stubs), wall valves + wheels,
  gauges with neon LEDs, and glass screens + LEDs on the 6 consoles.
- GDD room contents (DD_Props):
  * S3 Galley: plates/mugs/bowls on the tables + a pot on the counter.
  * S6 Sonar & Radio: split into TWO rooms with a CorrodedMetal partition + doorway.
    Moved the central emergency fixture into the sonar half and added a 2nd tagged
    EmergencyLight to the radio half so both stay lit + flicker (count 10 -> 11).
  * S7 Conning Tower: a small cockpit at the top (console + glass screen + seat +
    periscope eyepiece), decorative.
  * S9 Aft Torpedo: 2 torpedo tubes + twisted floor debris + a hanging broken panel
    ("similar to S1 but more damaged").
  * S2 Berthing: scattered belongings (helmet, duffel, boots, book).
  * S4 Officers: personal effects on the desk (books, mug, photo frame, lamp).
- Verified by automated playtest: clean boot, 0 errors; 11 emergency lights enabled;
  252 DD_ parts; S6 has 2 fixtures.

Notes for the team:
- BAKED ONLY (same caveat as session 9): MapBuilder was NOT updated, so a from-scratch
  regen returns without this dressing/props. (Light brightness/range + flicker ARE in
  MapBuilder, session 14.) Props live in per-section DD_Detail / DD_Props folders —
  easy to find / remove / tweak.
- Decorative parts are CanCollide=false (won't snag the player); the S6 partition is
  solid with a passable doorway.
- The GDD "sealed cylinder" hull was deliberately NOT built — Razvan chose textures +
  props over a geometry rebuild. Revisit if we ever want the true tube shape.
- Needs Ctrl+S to persist all of this.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 14 — emergency lights: brighter + pulsing flicker]

Type: Art / Tuning

Summary: Rooms were too dark even with the flashlight on. Per Razvan, leaned on the
red ceiling emergency lights: boosted them so they actually fill the room with a dim
red glow, and reworked the flicker so it SURGES (washes the room red) and stutters,
instead of only dimming.

What changed:
- Baked EmergencyLight fixtures (all 10: 9 sections + captain's room) — PointLight
  Range 15 -> 34 (a single ceiling-center light couldn't reach the ends of a 48x24
  room), base Brightness 0.6 -> 1.6, BaseBrightness attr -> 1.6. Color (255,45,28)
  and Shadows unchanged (Shadows stay ON so the red doesn't bleed through the walls
  between sections).
- Server/PowerManager.startEmergencyFlicker — rewrote the per-light loop: 1.5-4.5s
  of steady dim glow, then a burst that surges to ~1.3-1.8x base (lights the room
  red) and stutters down to ~0.2-0.5x, with an occasional brief brownout, then
  settles back to base. (Was: only dipped to 0.2-0.5x and back — never brightened.)
- Server/MapBuilder — synced addEmergencyLight + the captain inline light to the
  same values (Color 255,45,28 / Brightness 1.6 / Range 34 / BaseBrightness attr)
  so a from-scratch regen matches the baked look.
- Verified by automated playtest: base 1.6 / range 34 / enabled; over 6s the light
  ranged min 0.36 -> max 2.58 (dips + surges confirmed). Clean boot, 0 errors.

Notes for the team:
- Values are tunable. If still too dark, next levers: raise base Brightness/Range
  again, lift Lighting.Ambient (currently 8,14,22 in LightingSetup), or add a 2nd
  emergency fixture to the long sections (one center light still leaves the bow/stern
  ends dimmer than the middle).
- Needs Ctrl+S to persist the baked fixture changes.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 13 — locker exit fix + door numbers]

Type: Fix / Feature

Summary: Fixed "can't get out of a hiding locker" (E did nothing to exit), and put
the door numbers back as a close-up-only prompt (follow-up to session 12's label
removal).

What changed:
- Locker exit (Razvan bug). Root cause: the in-locker ProximityPrompt is unreliable
  once the player is teleported INSIDE the now-non-collidable part and frozen, so the
  second E press never re-triggers it. Rather than fight that a third time (see
  sessions 10/11), added a deterministic exit path:
    * Shared/Net — new C2S remote "ExitHide".
    * Client/InventoryUI — while the player's "Hiding" attribute is set, E fires
      ExitHide instead of useSelected(); otherwise E still uses the selected item.
    * Server/CreatureManager — Start() handles ExitHide -> toggleHide(player, locker).
      Added a 0.4s per-player debounce (lastToggle) at the top of toggleHide so the
      prompt + ExitHide can never double-toggle; cleared on PlayerRemoving.
  Verified by automated playtest: enter -> Hiding=true & moved inside; after the
  debounce, exit -> Hiding=false & original position restored. Clean boot, 0 errors.
- Door numbers. Session 12 removed the floating "Door X/7" labels; this restores the
  number where it only shows up close, in the prompt heading. Set DoorPrompt +
  SealPrompt ObjectText to "Door N/7" on all 7 baked doors (1/7..7/7), and mirrored
  it into MapBuilder.buildConnector (regen path) so a rebuild matches.

Notes for the team:
- Mobile: exit currently relies on the E keybind. If we ship mobile, add an on-screen
  "leave locker" button that fires ExitHide.
- Needs Ctrl+S to persist the baked door ObjectText.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 12 — remove floating interaction labels]

Type: Fix / Art

Summary: Removed the always-visible floating text labels from every interactable
so object names no longer broadcast across the room. The distance-gated
ProximityPrompt ("[E] Hide", "[E] Open", etc.) now does all the work — nothing
shows until the player is within 10 studs. Matches the GDD's no-hand-holding /
"fear comes from not knowing" rule (you can't spot a hiding locker from afar now).

What changed:
- Baked Workspace.Submarine — deleted all 20 "Label" BillboardGuis (each was
  AlwaysOnTop, MaxDistance 40): 3 hiding spots, 7 bulkhead doors, and 10
  consoles/panels (escape pod, notice board, captain door, safe, ballast, sonar,
  radio, generator, exterior passage, periscope). The ProximityPrompts
  (MaxActivationDistance 10) were left intact, so the [E] prompt still appears up
  close. Verified: 0 BillboardGuis remain under Submarine; prompts intact.
- Server/MapBuilder — removed the label() calls from makeInteractable,
  makeHidingSpot and buildConnector (plus the now-dead "Door X/Y" numbering
  computation) so a from-scratch regenerate matches the baked result. KEPT the
  label() helper + the section-5 ballast clue plate ("VALVE ORDER 3-1-4-2-5") —
  that one is intentional environmental storytelling, not an interaction prompt.

Notes for the team:
- Per Razvan: applied to ALL interactables, not just the doors/lockers he flagged,
  for consistency.
- Pickups + journals never had floating labels, so they're unchanged (they already
  relied on the proximity prompt alone — this just makes everything match).
- Trade-off: the door wayfinding numbers ("Door 1/7") are gone with the labels. If
  we want them back without the far-away spoiler, move the number into each
  DoorPrompt's ObjectText so it only shows when close. Easy follow-up if wanted.
- Needs Ctrl+S to persist the baked deletions.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 11 — hide exit, pod look, flashlight warm-up]

Type: Fix / Art

Summary: Fixed the can't-exit-locker regression, made the escape pod look like a
pod, and improved the flashlight first-use delay.

What changed:
- Server/CreatureManager.toggleHide — the session-10 fix ANCHORED the player in
  the locker, which blocked the exit ProximityPrompt (couldn't get out). Reworked:
  instead of anchoring, we set the locker CanCollide=false while occupied (so the
  solid block can't eject the player), drop them inside, and zero WalkSpeed/Jump.
  NOT anchored, so the same prompt toggles them back out (restored to their
  remembered standing spot; locker collision + movement restored). Stores walk+jump
  in hideData.
- Escape pod (Section_1) — was a flat console-grey box. Now an orange Ball
  (235,120,35, Metal, reflectance 0.1) sitting on the floor with a dark-glass
  porthole "PodWindow" — reads as an actual pod. Label -> "Escape Pod". Applied to
  the baked part + MapBuilder section 1 (regen). Launch interaction unchanged.
- Client/FlashlightController — the v7 warm-up used brightness 0.04, too faint to
  actually compile the lit-spotlight path, so the FIRST F press still hitched
  (worse now with the new PBR materials compiling). Replaced with a brief real
  warm-up kick at load (brightness 2 for ~0.45s, then 0.05 to 3s, then 0) so the
  shader/lighting path compiles up front and the first real press is instant. The
  delay was a Studio first-use compile artifact (much smaller on the live client).
- Disk synced (CreatureManager, MapBuilder, FlashlightController — the last was a
  long-stale on-disk copy, now current); syntax clean; installer rebuilt.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 10 — hiding spots fix]

Type: Fix / Art

Summary: Hiding spots looked like bare metal and dropping into one shoved the
player out BEHIND the cabinet (solid block + teleport-to-centre = physics eject).
Reskinned them as wooden lockers and rewrote the hide to anchor the player inside.

What changed:
- Hiding spots (3, tagged HidingSpot) — reskinned to WoodPlanks, colour 96,68,42,
  reflectance 0, cleared any metal MaterialVariant (baked). MapBuilder.makeHidingSpot
  updated to match for regen.
- Server/CreatureManager.toggleHide — rewrote: on hide we remember the player's
  current CFrame + WalkSpeed, set WalkSpeed 0, move the HRP to the locker centre
  and ANCHOR it (so the solid cabinet can't eject them) — they're now actually
  inside. On unhide we restore them to the remembered standing spot, unanchor and
  restore WalkSpeed. Added hideData table (+ cleared on PlayerRemoving).
- Disk synced (CreatureManager, MapBuilder); syntax clean; installer rebuilt.

Note: creature is still frozen (FreezeCreature=true), so the hide-vs-creature
behaviour itself isn't live-testable yet, but the get-in/get-out is.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 9 — textures + particles]

Type: Art / FX

Summary: First texture + particle pass on the baked Submarine. Removed the test
lights, did a built-in PBR material pass, generated + applied AI PBR material
variants, and added atmospheric particles. All on the baked Workspace.

What changed (all on Workspace.Submarine, baked):
- Removed the 25 session-5 TestLights. The sealed captain's room would have gone
  black, so added a proper dim-red EmergencyLight inside it (255,45,28 /
  Brightness 0.6 / Range 15 / BaseBrightness 0.6, tagged + Section=4) to match the
  other tuned fixtures. (Creature is STILL frozen — FreezeCreature=true.)
- Built-in material pass: walls -> CorrodedMetal (80), floors -> DiamondPlate (16),
  ceilings -> Metal (16), bulkhead doors -> DiamondPlate (7), bunks/tables/desks ->
  WoodPlanks (8), consoles -> Metal (8), generator -> CorrodedMetal, walkway ->
  DiamondPlate, plus small reflectance for a wet look. Lights/pickups/water/clue/
  breach left untouched.
- AI PBR (Roblox generate_material): created 3 MaterialVariants in MaterialService
  — deepdescent_hull_rust (CorrodedMetal), deepdescent_floor_grate (DiamondPlate),
  deepdescent_console (Metal) — and applied them to the 80 walls, 16 floors, 8
  consoles + generator. Texture maps generate async on Roblox's side, so they may
  take a short while to fully resolve; until then they fall back to the base
  material (no regression).
- Particles (built-in textures, no uploads): hull breach -> water spray + rising
  bubbles; generator -> steam + sparks; faint electrical arc sparks on every 3rd
  emergency fixture. Named DD_* for easy removal.

Notes for the team:
- This pass is on the BAKED geometry + MaterialService only; MapBuilder was NOT
  refactored to assign these materials/variants/particles, so a from-scratch
  regenerate would come back flat (same standing caveat as the baked lighting).
- The MaterialVariants + generated textures save with the place — Ctrl+S to keep
  them. Restart Play to see the captain-room light change.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 8 — ballast clue + feedback]

Type: Fix / Feature

Summary: The ballast valve combination had no in-world clue, and wrong presses
looked "accepted" (every press flashed green). Added a clue and fixed feedback;
hardened the puzzle input. Also clarified the cargo/secret-ending flow.

What changed:
- Combination clue — added a "BALLAST VALVE ORDER  3 - 1 - 4 - 2 - 5" plate
  (SurfaceGui) on the wall beside the ballast panel in Section_5_control_room
  (baked) and in MapBuilder section 5 (regen, via label()). The sequence itself
  is EndingData.BALLAST_SEQUENCE = {3,1,4,2,5}.
- Client/EndingClient — valve press feedback was GREEN for every press (looked
  like wrong inputs were accepted). Now neutral blue on press; a wrong entry
  flashes all valves RED (plus the existing "WRONG — SEQUENCE RESET").
- Server/EndingManager — added a ballastActive guard so inputs only count while
  the puzzle is open (set on BeginBallastPuzzle, cleared on success); added a
  Debug print of each input + expected step to diagnose any mis-entry. The core
  logic already reset progress on a wrong press and only surfaced on the exact
  order {3,1,4,2,5} — I could not find a path where a genuinely wrong sequence
  triggers the surface ending, so if it recurs, grab the Output "Ballast input.."
  lines.
- Disk synced; syntax clean (0 failures); installer rebuilt.

Cargo / secret endings (clarification, no change yet): taking the cargo at the
aft Hull Breach Passage (TakePrompt / key T, needs all 6 journals) only FLAGS
cargoTaken — it is not itself a win. You then complete ANY good ending (escape
pod / SOS / surface) and it upgrades to "hubris". Returning the cargo (the other
prompt) instantly triggers the secret-good "the_truth". There is no "walk out the
breach = win". Pending Razvan's call on whether to add a direct escape-with-cargo
win at the breach.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 7 — input/oxygen/tuning]

Type: Fix / Feature / Tuning

Summary: Door labels, ballast input rework, oxygen/breath, item-use UX, rescue
time. Also found+noted that the on-disk client scripts had drifted from the live
place.

What changed:
- Doors — labels were "Door secA/secB" which read as a gap (6/8, 8/9) because the
  hull skips the tower (7). Now sequential out of total: Door 1/7 .. Door 7/7.
  Updated both the baked BulkheadDoor billboards and MapBuilder.buildConnector.
- Client/EndingClient (ballast valve puzzle) — reworked: the cursor was stuck in
  the centre (first person locks it). Now while the panel is open we force the
  mouse free every frame via BindToRenderStep, AND accept keyboard 1-5 for the
  sequence; Esc / X / click-outside all close it. Sets the player attribute
  "UIModalOpen" while open.
- Client/InventoryUI — while UIModalOpen is set, the hotbar ignores keys so the
  1-5 combo entry doesn't also switch items. Also reworked item use to TWO-STEP:
  1-4 (or tap a slot) SELECTS (yellow outline); E (or tap the selected slot
  again — mobile) USES it. Right-click still drops. Stops battery/glow stick
  being spent the instant you equip them.
- Server/OxygenManager — drowning/breath now triggers when the player's HEAD is
  actually below the section's water surface (was: only when the whole section
  was >=80 flooded, so you could sit underwater forever). The breath bar already
  existed in HUD (shows on "danger"); it now actually appears + drains, and
  depletion fires the Drowned ending.
- EndingData / EndingManager — SOS rescue survival 8 min -> 2 min.
- Disk sources synced for all of the above; syntax clean (0 failures); installer
  rebuilt.

Heads-up for the team (IMPORTANT):
- The on-disk repo copies of some CLIENT scripts had drifted from the live place
  (FlashlightController and InventoryUI on disk were older than live). I work
  from the live place via MCP and re-synced the files I touched, but the disk
  tree / INSTALLER may still be stale for files nobody re-synced. Treat the LIVE
  place as source of truth; we should do a full live->disk re-export when
  convenient. (FlashlightController on disk is notably older than the live v6.)
- Session-5 test aids (FreezeCreature + TestLights) are still ON.
- Needs Ctrl+S to persist; client script changes need a fresh Play (Stop->Play).

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 6 — layout + UI fixes]

Type: Fix / Art

Summary: Fixed four issues Razvan flagged while testing: floating notice board,
the non-existent captain's quarters, the unusable ballast valve UI, and a
question about the section-9 opening.

What changed:
- Workspace.Submarine.Section_3_galley — NoticeBoard was floating in the stern
  doorway (was at the +X end wall, Z=0). Moved it flush onto the +Z (right) wall
  at x=cx+8, size now 6 x 4 x 0.4. Journal_3 re-pinned to the board face.
- Workspace.Submarine.Section_4_officers_quarters — the captain's quarters was
  just loose props (no room). Built a real enclosed room: a partition wall at
  Z=-3 spanning the section (CaptainWallL/R + CaptainWallTop) with an 8-stud
  doorway; repositioned CaptainDoor into that doorway (now thin in Z). The locked
  door (keycard) is the only way in — onCaptainDoor sets CanCollide=false on
  unlock, so it's not a trap. Added a light inside (baked: bright TestLight under
  CaptainLightRig; MapBuilder regen: a dim red EmergencyLight fixture) since the
  partition blocks the section lights.
- Client/EndingClient — ballast valve puzzle UX: (1) the mouse is now freed +
  cursor shown while the panel is open (first person locks it to centre, so you
  couldn't click the valves), restored to LockCenter on close; (2) full-screen
  click-catcher behind the panel dismisses it on an outside click (also dims the
  scene); (3) added an "X" close button top-right of the panel.
- Server/MapBuilder — synced both geometry fixes into source (notice board +
  captain room) so a from-scratch regenerate matches the baked layout.
- Disk sources synced; syntax clean (0 failures); installer rebuilt.

Section-9 opening (answer to Razvan's question): that's intentional, not a bug.
buildSectionShell leaves the stern cap of section 9 partly open as the hull
breach (GDD 4.1 / 5.1: jagged hole with water particles) and the exterior secret
passage for the secret endings (SectionData hasExteriorPassage). Right now it's a
plain gap (SternCapL + SternCapTop only). Can dress it as a proper jagged breach
with water spray, or seal it, on request.

Notes for the team:
- Geometry fixes were applied to the BAKED Workspace (what renders) AND mirrored
  into MapBuilder. The session-5 test aids (FreezeCreature + TestLights) are still
  active — revert those before a real lighting/playtest pass.
- Needs Ctrl+S to persist.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 5 — test aids]

Type: Tuning / Test aid (TEMPORARY — revert before launch)

Summary: Added full map lighting and froze the creature so the whole submarine
can be walked to test layout/navigation without darkness or the monster.

What changed:
- Workspace.Submarine — added 24 PointLights named "TestLight" (each under an
  invisible anchored "TestLightRig" part), spread through every section (2 in the
  larger ones), the conning tower, and all 7 connectors. Brightness 6, Range 60,
  Shadows OFF (stays within the Realistic shadow budget). Independent of the power
  system, so always on. To REMOVE: delete every part named "TestLightRig".
- Shared/GameConfig — added GameConfig.FreezeCreature = true (new test flag).
- Server/CreatureManager — step() early-returns when GameConfig.FreezeCreature is
  true, so the creature still spawns (silhouette in section 9) but never moves,
  hunts, or kills. Set FreezeCreature = false to restore normal behaviour.
- Disk sources synced (GameConfig.lua, CreatureManager.lua); installer rebuilt.

Notes for the team:
- TEMPORARY. Before any real lighting/playtest pass: set FreezeCreature = false
  and delete the TestLightRig lights (they blow out the intended dark mood). The
  lights live only in the baked Workspace (not in MapBuilder), so a from-scratch
  rebuild won't include them.
- Needs Ctrl+S to persist the lights to the saved place.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 4 — lighting]

Type: Art / FX / Tuning

Summary: First lighting pass on the (now baked) fixtures. Per Razvan: darker /
flashlight-reliant, keep the deep emergency red, add an occasional subtle flicker.
Applied directly to the baked instances + a runtime flicker in PowerManager.
Verified by playtest (no errors; emergency brightness flickered 0.6 -> 0.12 -> 0.6).

What changed (applied to the baked Workspace.Submarine fixtures):
- EmergencyLight (9 PointLights, always on): Color -> 255,45,28 (richer red);
  Brightness 1.2 -> 0.6; Range 18 -> 15; attribute BaseBrightness=0.6; Shadows kept
  on. Fixture bulb color -> 150,24,14.
- MainLight (16 SpotLights, off until main power): Color -> ~226,232,244; Angle
  120 -> 100; Range 30 -> 34; Shadows true -> FALSE (16 shadow-casters was over
  Roblox's budget under Realistic lighting).
- Server/PowerManager: added startEmergencyFlicker() — per light, 2-8s steady then a
  brief stutter down to ~0.2x base and back; reads the BaseBrightness attribute;
  called from Start().

Heads-up / TODO: lighting is tuned on the BAKED instances (the live source of
truth). MapBuilder.addEmergencyLight/addMainLight still hold the OLD pre-tune
values, so a from-scratch regenerate (delete Submarine -> rebuild) would revert the
look until those defaults are synced. Sync them once lighting is finalized.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 4]

Type: Refactor / Workflow

Summary: Baked the procedural submarine into static, editable geometry. It used
to rebuild from MapBuilder every server start (Workspace was empty in Edit mode);
now it's real saved geometry you can see/light/decorate by hand, and the runtime
reuses it instead of rebuilding.

What changed:
- Workspace.Submarine — now a permanent baked model: 16 models (8 sections +
  conning tower + 7 connectors) + StartSpawn; 285 parts, 45 prompts, 26 lights.
  Attribute Baked=true. All gameplay tags/attributes intact (WaterPlane 8,
  EmergencyLight 9, MainLight 16, BulkheadDoor 7, Interactable 14, Pickup 11,
  Journal 6, HidingSpot 3).
- Server/MapBuilder — Build() now checks for an existing Submarine with the Baked
  attribute and uses it as-is (skips the runtime rebuild). To regenerate the
  layout from code, delete the Submarine folder (or clear its Baked attribute)
  and play once / re-run the bake.
- The bake itself was run from the Studio Command Bar (Weppy's execute_luau
  sandbox blocks `require`, so it can't invoke MapBuilder directly).

Verified by playtest: exactly 1 Submarine at runtime, Baked=true, all tags
resolve, no errors.

Notes for the team:
- The map is now editable static geometry in Workspace — light it and add props
  by hand. Don't rename the "Submarine" folder or drop its Baked attribute unless
  you want the procedural builder to take back over.

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 3 fix 4]

Type: Fix / Perf

Summary: The flashlight beam sometimes took up to a minute to first illuminate
after being turned on. Ruled out the map build (MapBuilder is synchronous, no
yields -> built in ~1 frame) and the data path (BatteryUpdate is instant and
re-sent every 0.5s while on). It's a Future-lighting "first-use hitch": the
engine spins up its spotlight lighting/shader path the first time a beam lights
the scene (worst during Studio's first minute while shaders/assets load).

What changed:
- Client/FlashlightController — pre-warm the beam at load (enable at an invisible
  brightness ~0.02 for ~1s, then drop it) so the lighting pipeline initializes
  before first real use. Load marker bumped to v6.

Notes for the team:
- Any residual first-use delay is largely a Studio-playtest artifact; expect it
  to be much smaller on the published client. Confirm the live build via Output
  ("FlashlightController loaded — single-circle build v6").

----------------------------------------------------------------------------
2026-06-29 — Claude (Claude Code)  [session 3 fix 3]

Type: Fix

Summary: Fixed the "flashlight light goes chaotic / all over the place"
(intermittent; cleaned up after moving around). Cause: the new reflective +
bobbing Glass water surface threw shifting flashlight glints; on dry surfaces the
beam was already a clean circle.

What changed:
- Client/WaterRenderer — water surface Reflectance 0.25 -> 0.05 and the volume
  Reflectance 0.05 -> 0. Keeps the Glass refraction (still reads as water) but
  kills the moving-glint chaos when the flashlight hits the surface.
- Client/FlashlightController — beam now tracks via BindToRenderStep (Camera
  priority + 1) reading the live CurrentCamera, so it can't lag a frame or follow
  a stale camera. Load marker bumped to "build v5".

Notes for the team:
- If the flashlight misbehaves again, check Output for the
  "FlashlightController loaded — single-circle build vN" line to confirm the
  client actually reloaded (LocalScripts only reload on a FRESH playtest:
  Stop, then Play).

----------------------------------------------------------------------------
2026-06-28 — Claude (Claude Code)  [session 3 fix 2]

Type: Fix / Tuning

Summary: Flashlight beam refined to a single clean circle. Removed the wide
"spill" light (it caused a splattered, "all over the place" look) and the
forward light offset (it made the beam vanish up close, because the origin got
pushed into the wall/door surface).

What changed:
- Client/FlashlightController — now ONE SpotLight (Angle 44, Range 60,
  Brightness ~3.2) with its origin exactly at the camera. Shadows still off so
  it lights whatever you point at.

----------------------------------------------------------------------------
2026-06-28 — Claude (Claude Code)  [session 3 fix]

Type: Fix

Summary: Flashlight stopped lighting surfaces after LightingStyle was switched to
Realistic. Cause: the beam SpotLight sits at the camera (inside the player's
head); under Realistic's per-pixel shadows the head/body self-shadowed the beam,
blacking out everything the player looked at.

What changed:
- Client/FlashlightController — set the beam SpotLights' Shadows = false so the
  player's own (first-person-invisible but shadow-casting) body can't occlude the
  beam; pushed the light origin ~1 stud forward; bumped brightness (hotspot
  2.6 -> 3.6, spill 0.7 -> 1.0) since Realistic renders darker.

Notes for the team:
- Lesson: a shadow-casting light parented at the first-person camera self-shadows
  on the character under Realistic lighting. Keep the flashlight's Shadows off.

----------------------------------------------------------------------------
2026-06-28 — Claude (Claude Code)  [session 3]

Type: Art / FX

Summary: Reworked the flood water so it reads as water instead of a flat tinted
box. Client-side only (WaterRenderer); verified clean boot (8 water planes, no
errors).

What changed:
- Client/WaterRenderer — the water volume now uses Glass (refraction), tinted
  darker with depth; added a reflective Glass surface "skin" at the waterline
  that gently bobs + shimmers; added rising bubble particles inside flooded
  volumes; going under now adds a stronger blue overlay + a BlurEffect (on top
  of the existing underwater reverb). Built-in materials/effects only — no
  external asset IDs.

Open items / next steps:
- Needs a visual pass from Razvan: tune tint, surface bob amount, bubble rate,
  blur strength to taste.
- Optional later: foam waterline trim and caustics (caustics would need a
  texture asset).

Notes for the team:
- Water visuals are 100% client-side; FloodManager only broadcasts levels.

----------------------------------------------------------------------------
2026-06-28 — Claude (Claude Code)  [session 2 cont.]

Type: Fix / Tweak

Summary: Flashlight follow-ups — moved the in-hand model to the LEFT hand (so
the right hand is free for another item) and resolved the "beam won't light
some walls" report (it was the lighting pipeline).

What changed:
- Client/FlashlightController — VIEW_OFFSET mirrored to the left hand
  (x = -0.9, yaw mirrored). Beam still cast from camera center.
- Server/LightingSetup — replaced the obsolete "Lighting.Technology = Future"
  line with "LightingStyle = Realistic" + "PrioritizeLightingQuality = true".

Lighting note for the team:
- Roblox REMOVED Lighting.Technology on 2025-01-21 and replaced it with
  LightingStyle (Future -> Realistic, ShadowMap -> Soft, Voxel removed) plus
  PrioritizeLightingQuality. The place is now LightingStyle = Realistic
  (verified) — the per-pixel pipeline the flashlight needs. Set it via the
  Lighting object's LightingStyle property, NOT the old Technology enum.
- Engine limit: a single light's Range caps at 60 studs, so the flashlight
  cannot light surfaces farther than ~60 studs (not a bug).

----------------------------------------------------------------------------
2026-06-28 — Claude (Claude Code)  [session 2]

Type: Feature / Fix

Summary: Reworked the flashlight from "always-on, no slot" into a dedicated
equip/holster tool with its own UI slot (toggle F), a focused circular beam,
and a first-person in-hand model. Verified by playtest (clean boot, no errors,
battery drain-gating correct).

What changed:
- ReplicatedStorage/Shared/Net — added C2S event FlashlightToggle.
- Server/BatteryManager — added equip/holster state; the flashlight is granted
  on pickup but starts OFF; battery now drains ONLY while on (holstering saves
  charge); handles FlashlightToggle; BatteryUpdate payload extended to
  (charge, max, on, flicker, hasLight, equipped). New API: HasFlashlight,
  SetEquipped, ToggleEquip.
- Client/FlashlightController — beam is now a tight hotspot SpotLight (Angle 30,
  Range 60) + a soft wide spill, cast from the camera so the lit circle sits on
  the player's point of view; added a first-person in-hand flashlight model that
  appears only while equipped.
- Client/InventoryUI — added a dedicated flashlight slot left of the 4 (F badge,
  battery bar, highlight when on); F key or click toggles; reads new payload.
  The 4 item slots are unchanged.
- Server/InventoryManager — pickup line now reads "Press F to switch it on."

Design note: per Razvan, the flashlight is a DEDICATED slot, NOT one of the 4
(keeps the GDD's inventory pressure). It starts holstered on pickup.

Open items / next steps:
- Visuals still greybox; tune beam brightness + in-hand model offset to taste.
- Audio still silent (SoundData.Ids all rbxassetid://0).

Notes for the team:
- New keybind: F = flashlight on/off. Other keys unchanged (Ctrl/C crouch,
  Shift run, 1-4 item slots).

----------------------------------------------------------------------------
2026-06-28 — Claude (Claude Code)

Type: Review / state audit (no gameplay changes)

Summary: Re-oriented on the project, verified the live place and code tree are
intact, confirmed the outstanding gaps, and set up this in-Studio dev log.

What I checked:
- Weppy connected to canonical place "Place1" (placeId 95779056096948),
  Team Create, Pro tier. Place was at version 14.
- Full script tree present and matches code-complete state:
  - Shared (9): SectionData, ItemData, CreatureData, EndingData, SoundData,
    MonetizationData, GameConfig, Net, + Assets/ItemModels.
  - Server (15): Bootstrap, LightingSetup, and managers Flood, Oxygen, Power,
    Creature, Inventory, Battery, Ending, Data, Monetization, Polish,
    Interaction, MapBuilder, ItemModels.
  - Client (10): CameraController, FlashlightController, HUD, InventoryUI,
    WaterRenderer, SoundProducer, AudioManager, EndingClient, MenuUI, Reticle.
- Read SoundData: every SoundData.Ids entry is still "rbxassetid://0"
  (placeholder). Audio logic is wired but the game is silent.

What I changed:
- Created this DevLog (ServerStorage.DevLog: README + WORKLOG). No game logic
  or instances touched.

Open items / next steps (unchanged):
1. Audio (#1 gap): wire real rbxassetid:// values into SoundData.Ids.
2. Final art / PBR textures (greybox only).
3. Monetization IDs in MonetizationData all 0 — need real IDs from Creator Hub.
4. Clean-boot verification — not yet playtested end-to-end this session.

Notes for the team:
- Intentional deviations from CLAUDE.md to keep: networking via the Net module
  (not loose RemoteEvents); creature uses section-waypoint movement (not
  PathfindingService — future upgrade).

----------------------------------------------------------------------------
TEMPLATE (copy below for new entries)

YYYY-MM-DD — <your name>

Type: Feature / Fix / Tuning / Art / Audio / Review / Other

Summary: One or two sentences on what this session accomplished.

What changed:
- <script or instance path> — what changed and why. For tuning, give old -> new.

Open items / next steps:
- ...

Notes for the team:
- Gotchas, decisions, questions for the others.

]==]
