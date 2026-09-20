# Worker B — shared task list

B maintains the sections above A's coordination log. Completed task branches
must now merge into main, which is the shared latest game. Historical branch
entries retain their original validation and do not claim every release gate passed.

**Current ownership:** B owns combat, bot assets/models/weapons, bot-customisation
menus and player controls. A owns other menus, networking, game rules, game world
and audio. Historical labels below describe authorship, not current ownership.

**Latest B task:** `codex/b-visual-budget`, from main `e9dd2b7`.
**Latest increment:** Measured geometry/LOD and two/ten-bot native visual load; [evidence and limits](coordination/B_VISUAL_BUDGET.md). User requested pause after the audit. Impact feedback is merged on main `e9dd2b7`.
**Next:** Finish the 1v1 game: combat/bot/control feel and remaining garage/customisation work. A prioritizes external 1v1 hosting and HUD. Current base includes protocol-4 networking and all five weapons.
**Intent and evidence:** [Supplied menu integration](coordination/B_MENU_KIT.md).
**Integration guide:** [B handoff](DEVELOPER_B_HANDOFF.md).

## Completed B increments

- [x] **B-00:** Shared task list, ownership boundaries and per-increment handoffs.
- [x] **B-01:** 50m arena, walls/chamfers, team/FFA markers, third-person orbit
  camera, collision, zoom/recenter and horizon stabilization.
- [x] **B-02:** Read-only resource HUD with missing/invalid-value handling.
- [x] **B-03:** Local camera preferences, live settings panel, save/cancel/defaults.
- [x] **B-04a:** Explicit Resume/Settings/Return in the standalone preview, keyboard
  navigation, deferred return, cancel-on-menu/focus-loss, and held-action rearming.
  Uses A's required brake+secondary cancellation. Standalone real-lifter fixture,
  camera/settings regressions and A's duel/navigation checks pass.
- [x] **B-04b:** Independent X/Y sensitivity; keyboard/mouse binding capture,
  validation, save/cancel/defaults and hold/toggle primary. Separate local
  persistence; menu/focus/lifecycle cancellation and physical release-to-rearm.
  Independent b_controls scene, model/combat/GUI tests and rendered layout.
- [x] **B-06:** Session-wired compact network state and expanded build/mode/local
  physics/RTT/correction/interpolation/counters. Fresh-snapshot gating and typed
  unavailable values prevent stale or fabricated telemetry. Standalone scenario,
  real UDP impairment/recovery, keyboard cancellation and app layout tests pass.
- [x] **B-07a:** Practice and real UDP host/join/ready enter a playable arena; authoritative teams/builds/readiness, keyboard menus, pending feedback and phase locks. Remote JSON team IDs fixed without changing the public API.
- [x] **B-08a:** In-arena phase, round, clock, scores and authoritative outcomes; Practice unscored. Countdown/intermission/results preserve arena view while input stays gated. Real two-player full-match and independent HUD tests pass.
- [x] **Menu kit integration:** Supplied eight-screen design now owns default F5. Real practice/duel/2v2 lobby flow, canonical build editing/local saves, real Settings, and scaled native UI. Detailed validation is in B_MENU_KIT.md.
- [x] **AB-01 automated compatibility:** Published A/B integration mounts the real
  session through BotSource with B arena/camera/HUD. This is not human LAN acceptance.

## Active and next — B-owned

**B handoff to A:** `codex/b-garage-test-drive` adds a separate B entry through
menu_game's Garage/Customize composition. Existing practice authority and selected
arena remain; Back to Build restores the originating screen and in-memory history.
Hidden workshop processing is disabled while driving. No wire, physics or save
schema changes. Sawblade/physical-legs model, registry, drive and Customize integration is now merged on main `7ce48ab`. See [test-drive scope](coordination/B_GARAGE_TEST_DRIVE.md).

User priority update (2026-09-20): a fully working 1v1 game comes first. Defer
2v2, FFA and other multiplayer modes, plus all tutorial work, until then. A owns
the raised HUD priority and external matchmaker/server deployment; B supplies
combat/bot state and feedback through the shared interfaces.

A also prioritizes general menu refinement, especially integrating multiplayer
and networking screens with the original menu system's design and navigation
(user feedback, 2026-09-20). B retains garage/customisation ownership.
A's high-priority menu scope also includes finished 1v1 win/score screens and an
in-game menu page matching the other panels. Existing results code does not close
these newly requested presentation tasks.

- [ ] **Combat and bots:** Maintain damage/resources/recovery, weapon mechanics
  and visuals, bot assembly/catalogue and model integration. Investigate combat
  defects handed off by A's network/match-flow checks.
- [ ] **Controls and camera:** Player input/driving, camera and spectator control
  behavior, including control-specific settings. Consume A's match phase and
  spectator sources; do not calculate local winners or ready state.
- [ ] **B-09: Full garage.** Supplied kit edits/saves canonical builds with validation and paint; per-build undo/redo, live 3D preview, comparisons, individual invalid-build repair, explicit disk/backup recovery, 150% text and direct unsaved-build Test Drive are implemented. Authored Sawblade modules, paint, drive variants and walking legs are now integrated on main `7ce48ab`; human build/handling acceptance remains open. APIs: ContentRegistry.validate/starter and
  LoadoutStore.save/load_saved; preview unsaved builds, show specific validation
  reasons, preserve invalid builds for repair. These APIs are available now.

## Later B scope and acceptance still open

- [ ] **B-10:** Weapon animation/VFX from authoritative state/events. A owns audio.
  Authored Sawblade weapon animations and drive variants are integrated on main `7ce48ab`; snapshot-driven damaged/disabled component stages are integrated on `7026da6`. Confirmed impact sparks/fragments now have bounded pools and lifecycle checks. Larger-scene budgets, human readability and legacy CLI mounting remain open. Coordinate shared content identity and network-state changes with A.
- [ ] **B-11:** Control accessibility/controller behavior and bot-customisation
  polish. A owns general tutorial/menu presentation and audio.
- [ ] **B-12:** Optional first-person camera after third-person feel is accepted.
- [x] **AB-02 human multiplayer:** User reports successful multiplayer through a
  tunnel on 2026-09-20. This does not certify external hosting or specific measured
  contact/camera/recovery thresholds.
- [ ] **Gameplay acceptance:** Fully working 1v1 combat with clear weapon/damage
  feedback and complete hosted round/results/rematch flow. Human tunnel play has
  succeeded; externally hosted play remains outstanding.
- [ ] **Deferred tutorial:** B's control exercises/progression and A's menu entry
  wait until the 1v1 game is fully working, alongside 2v2 and other modes.

## Editing and branch boundaries

B owns combat/bot/weapon implementation, bot assets, garage/customisation and
player controls. A owns general menus, networking, match rules, world/arena and
audio. Tests follow feature ownership. TEAM_WORKFLOW.md maps mixed folders and
shared interfaces; old a_/b_ scene prefixes do not override the current split.

Former B arena readability, lobby/loading/results, general HUD/menu and audio
todos transfer to A. Former A combat/weapon/drive/bot-assembly maintenance
transfers to B. Shared APIs stay compatible unless a coordinated change says otherwise.

Use a focused branch per independent feature. B-04 starts from the published A/B
integration because it tests real combat cancellation; it does not inherit the
unrelated art branch. Use isolated worktrees when another task has local edits.
After each increment: relevant checks, commit task files, fetch, rebase onto main
**with --rebase-merges for this integrated history**, then push. Preserve the A/B
merge; flattening it replays both teams' old documentation edits as false conflicts.
After checks, merge the completed task locally into main and push main directly.
Main now contains the integrated game; begin the next task from updated origin/main.

## B response to A — B-04a

- Your brake+secondary cancellation request is implemented in both immediate
  release and every suppressed physics tick, including standalone fixtures.
- Keep SessionBotSource.input_allowed; lifecycle suppression remains A's concern.
- Existing preview APIs remain; A may continue hiding its CanvasLayer.
  The standalone return is now explicit/deferred; Escape never exits it.
- B will not edit A's live menu implementation. A's latest Escape fix is included
  in this branch's base, and its real-duel/navigation regressions pass unchanged.
- The settings focus order skips disabled recenter strength and loops through
  visible controls. A's session menu still owns its own focus policy.
- No input action, BotCommand field or wire-version changes are required.

## Developer A — current coordination

- **A Moon arena:** isolated `codex/a-moon-arena` adds Lunar Outpost terrain, low gravity
  and general-menu selection, preserving octagonal bounds/spawns
  and Foundry wire compatibility. Moon uses existing body gravity_scale and replay. Reserves arena scripts/materials/scenes, selector menu
  files and tests. No B assets, controls or combat edits. See
  [Moon coordination](coordination/A_MOON_ARENA.md).

- **1v1 core HUD implemented:** `codex/a-duel-hud` adds read-only resources,
  component diagram, weapon/recovery state, immobilization, heading and duel bot
  status plus original-theme round presentation. B-owned combat/control/camera/
  bot/garage code is unchanged. Local `MvpSession.bot_views()` returns detached,
  snapshot-initialized data; no wire/schema change. See [HUD evidence](coordination/A_DUEL_HUD.md).

- **1v1 menu panels implemented:** A refined online/direct-connect/lobby panels,
  added win/score tabs and composed an original-theme in-game menu on
  `codex/a-duel-menu-panels`. B combat/control/camera/garage paths are untouched.
  Baseline, detached/rendered panels, real HTTP/ENet online lobby and real two-peer
  results/rematch pass. The four new fixtures are registered in the presentation
  runner. See [evidence and integration](coordination/A_DUEL_MENU_PANELS.md).

- **A Foundry arena complete:** `codex/a-foundry-arena`, rebased onto audio/practice.
  User-requested regular octagon, eight industrial cage/gallery bays, worn steel,
  radial roof and staged overhead/perimeter lighting. Spawn transforms retained.
  Shared camera scene's existing corner_chamfer is 14.644661; no control algorithm
  edits. Build 11 rejects square-map peers. Baseline, arena, camera, rendered and
  real-ENet wall checks pass. Human art review remains open. See
  [Foundry coordination](coordination/A_FOUNDRY_ARENA.md).

- **Practice loop:** A reserves practice restart in MvpSession, menu-shell
  composition and a new read-only target HUD. Reuses existing reset_round and
  BotView; no combat/control/bot/arena changes. Arena development remains in its
  separate worktree. See [practice scope](coordination/A_PRACTICE_LOOP.md).
  Validated: baseline, HUD/menu/state reset tests and actual two-peer match flow
  passed. Reset fixture also landed a real hammer hit after repair. No B changes.

- **Gameplay audio:** A reserves new audio controller/sound-bank/preferences,
  independent Audio settings panel and general menu-shell integration on
  `codex/a-gameplay-audio`. Reads combat events and match/bot views; no B combat,
  bot, control or customisation edits. Original menu melody remains. See
  [audio scope](coordination/A_GAMEPLAY_AUDIO.md).
  Implemented and validated: focused cue/settings/menu tests, baseline and actual
  two-peer countdown/results/rematch all pass. Complete by direct merge/push to
  main (published as 7feb900). First-pass procedural sounds; spatial mix and
  listening polish remain.

- **Merge-down rule:** Completed branches must merge into shared main after
  validation, then push main directly. No PRs. A feature-branch push alone no
  longer completes an increment.
  A is consolidating the completed A/B history and the current ownership/duel
  check. Future tasks start from updated origin/main. In-progress work stays
  separate and must be identified explicitly.

- **Ownership revision applied:** A = menus/networking/game rules/game world/audio;
  B = combat/bot models and weapons/bot-customisation menus/player controls.
  AGENTS.md and TEAM_WORKFLOW.md now govern current ownership. Earlier entries
  in this log preserve history only; new combat fixes are handed to B.

- **Actual duel combat loop:** A is checking canonical bots using real commands,
  weapon damage and normal match rules through results/rematch, since the existing
  menu fixture ends rounds by forfeit. Owns independent A integration fixture and
  demonstrated A fixes only; no B assets/UI or ten-player work. See
  [duel plan](coordination/A_DUEL_COMBAT_LOOP.md).

- **Small-match playtest packaged:** Windows `battlebots-gameplay-8433dc0.zip`
  includes the merged B results/rematch screen and menu music. Exported menu
  startup and dedicated server plus two independent clients reached active.
  Practice/LAN instructions are included; public service deployment is pending.
  Exact artifact hash and known shutdown warning are in HANDOFF.md.

- **User priority correction:** Stop ten-player expansion, bandwidth optimization
  and soak work; remove them from active todos. Focus on playable 1v1/2v2 combat
  and the complete player flow. Existing larger modes and historical evidence
  remain in the code/docs, but do not create further work or release gates.
  No snapshot codec changes were made before this correction.

- **Results integration:** A is integrating published B `cc49a15` with hosted
  `2eefc31` on `codex/a-results-integration`. Both results/rematch presentation
  and online membership cancellation/error routing are preserved in the shared
  menu shell. A registers the results fixture in CI and validates combined flows;
  B's modelling checkout and active unpublished work remain untouched. Evidence:
  [integration notes](coordination/A_RESULTS_INTEGRATION.md).

- **Hosted online play (in progress):** `codex/a-hosted-matchmaking` from
  performance `3f0e80f`. User requests removing tunnelling and offers Fly.io or
  Cloudflare. A is building Fly-hosted matchmaking plus dedicated ENet servers,
  guest admission, private friend codes and a 2v2 queue. Minimal online menu/client
  integration is explicitly part of this request; A reserves those routes along
  with services/networking, tests and deployment. Model/art paths stay untouched.
  [Scope and shared contract](coordination/A_HOSTED_MATCHMAKING.md). Build 10;
  deployment, full soak and public-service release acceptance are not yet passed.

- **Performance/reliability (in progress):** `codex/a-performance` from saw
  `5d3fd30`. A reserves independent process/performance fixtures and demonstrated
  network fixes. Ten real command-driving clients will exercise all five weapons,
  normal matches/rematches and measured budgets. No B assets/UI or modelling edits.
  [Scope and acceptance](coordination/A_PERFORMANCE.md); prior intermittent CI
  observer failures remain strict gates, with diagnostics now available.
  Build mvp-ab-9/protocol 4 adds reliable transition/one-second bot checkpoints;
  `combat_event.kind` is a canonical weapon ID or `ram`. Both peers must update.
  Saw CI passed all A checks, then exposed B's stale fourteen-part catalogue
  assertion. A repaired only `menu_customization_screens_test.gd` to check every
  registry part and all five weapons; its targeted check passes. No production
  B UI/assets or modelling checkout edits. Baseline and contact 80/150 ms pass.

- **Saw (implemented):** `codex/a-saw`, based on hammer `9610946`. A changed
  combat state/world, catalogue/save migration, primitive assembly and independent
  test/check paths. B's assets, menus/input and modelling worktree stay untouched.
  `saw` uses existing active/charge view fields; held primary consumes 9
  battery/14 heat per second, with 6 raw damage per 1/3 second of maintained contact.
  Independent state/physics/visual and ENet 0/80/150-ms checks pass. See
  [scope and acceptance](coordination/A_SAW.md). Build mvp-ab-8/protocol 4.
  All five weapon families are implemented; performance/soak and services remain.

- **Hammer (implemented):** `codex/a-hammer` on horizontal spinner `b46084e`;
  [scope and evidence](coordination/A_HAMMER.md). Adds hammer/Duelist, committed
  windup/strike/recovery and primitive arm animation, build mvp-ab-7/protocol 4.
  PlayerProfile now includes three starters. GameplayInputGate keeps a physical
  press edge on both toggle clicks; the held latch and lifter release stay intact.
  B can animate `windup` with charge, `strike`, and `cooldown` with its timer.
  Independent state/physics/input/menu/network checks pass. No modelling changes;
  the menu/music playtest ZIP remains untouched. Saw and performance/services follow.

- **Horizontal spinner (implemented):** `codex/a-horizontal-spinner`, based on menu
  export `db87257`. A historically implemented CombatState/CombatWorld, catalogue, loadout migration,
  primitive bot weapon visual and independent state/physics/ENet scenes. Add
  horizontal_spinner (30 kg/40 power), two-second charge, 40 max raw impact,
  60% charge consumption, 0.3-second target cooldown and lateral recoil.
  B can keep using existing charge/state/view fields; no new input actions.
  The published menu ZIP remains unchanged. Hammer/saw remain subsequent work;
  modelling worktree/assets are untouched. Independent state/physics/visual/save
  checks and real ENet at 0/80/150 ms pass; build mvp-ab-6/protocol 4. See
  coordination/A_HORIZONTAL_SPINNER.md for measurements and remaining gates.

- **Menu-flow correction (user requested):** `codex/a-menu-flow`, based on
  `d417d7e`. A is editing the supplied router/main/mode/lobby/garage scripts and
  main scene, with focused menu tests. Main exposes Host, Join, Practice and
  Garage. Join goes directly to the endpoint; host chooses mode then lobby;
  a sole map and mandatory garage are removed from play setup. All existing
  modes use the same lobby; selected builds can change there. No modelling
  assets or physics are being edited. Export this correction before resuming
  A's remaining spec work on another branch.

- **User-requested wind-down integration:** `codex/a-b-playtest` merges FFA
  `b71cb9b`, menu kit `595c8f9`, results intent `0f343f7`, Flamebot `909b666` and
  sawblade `5e163af`. The new menus are default F5; their four-slot frontend keeps
  duel/2v2 while a labelled button opens A's 5v5/FFA setup. Runtime art mounting is
  deferred; saw source is ignored by Godot until exported. Separate modelling
  checkout remains untouched. See coordination/A_PLAYTEST_INTEGRATION.md.

- **A completed mode increment:** `codex/a-ffa` from `e118f91`; intent and
  contracts are in [FFA coordination](coordination/A_FFA.md). A reserves session,
  MatchState, spawn selection, A app and independent tests. FFA uses unique entity
  teams and explicit placement/shared-winner results. B/model files remain untouched.
  B's observed match HUD `d983612` and results intent `0f343f7` are acknowledged,
  now imported in the playtest branch. The results event remains the detailed-stat source; on FFA it now
  also carries `match.winners` and `match.placements`. A's shell remains separate
  until an explicit integration checkpoint preserves B's final UI and input owner.

- **Playable checkpoint:** codex/a-b-integration at bdb42ef; CI passed. Includes
  2-player 1v1 / 4-player 2v2, session-specific menu actions and the Escape fix.
  Build mvp-ab-2, protocol 3. Both peers must run matching builds.
- **A implementation branch:** codex/a-ffa, based on 5v5 e118f91 and transport fix df509a0
  (which builds on contact 7235e50 and bdb42ef). A reserves
  networking, match/spawn simulation, A app hosting, independent test scenes and check
  scripts. Scripted contact/airborne/reset checks now exist at 0/80/150 ms;
  broadened transport/collision coverage and manual LAN remain next.
- **Modelling separation:** sawblade-tank at observed 5ec8dbb is visible remotely; A has not
  imported it. The separate flame modelling worktree is untouched. A will not edit
  assets, B presentation/UI/arena files, or weapon geometry during this increment.
- **B dependencies available:** ContentRegistry/LoadoutStore; session lobby/match
  views and request API; SessionBotSource input/camera proxy; spectator_sources.
  Exact contracts are in CONTRACTS.md. B-06–09 can consume these APIs.
- **Input integration:** A's proxy cancels menu/focus-suppressed weapon commands
  with brake+secondary. B should retain that cancellation in its final adapter.
  Standalone B preview Escape should consume input before a deferred scene exit;
  the MVP app now intercepts Escape and does not leave the live match.
- **Outstanding acceptance:** real two-computer LAN, human contact/camera/weapon
  feel, and broader contact/transport coverage beyond scripted cases. No localhost test is reported
  as a completed LAN playtest.
- **A progress:** isolated Jolt/replay comparison reproduced missing gravity and
  roll/pitch during airborne prediction. Fixed in simulation only; 250 ms replay
  error fell from 0.327 m / 75.99 degrees to <0.001 m / 0.04 degrees. New independent
  scene: tests/network/airborne_replay.tscn. No art, B files, or wire/API changes.
  Follow-up contact measurements are recorded below.
- Prior A coordination entries are preserved in archive/A_COORDINATION_2026-09-19.md.

- **A contact increment:** fixed over-replay of external motion, early visual
  offsets, missing reconnect velocities, pending reset baselines, and acceptance of old-round snapshots.
  Private ping/baseline/epoch messages now require mvp-ab-3/protocol 4 on both peers.
  Public session/BotSource APIs are unchanged. Independent contact and clock scenes
  cover launch/flip, lifter, spinner, ram, recovery, reset, clock origins/reconnect.
  Scripted settling is <=250 ms at 80 ms (0.25 m/10 degree
  tolerance). Broader collision cases and real LAN remain open. B input-menu work
  through 6e42594 and controls intent at d53967e are acknowledged, not yet imported.
  A retains SessionBotSource.input_allowed and live-session navigation ownership.
  No presentation/app/input or modelling changes here.
  Network checks run at real-time speed: accelerated ENet was observed throttling
  packets independently of the configured simulated loss. A subagent independently
  validated clocks/baselines and the real 120-render/60-physics case.

- **A completed transport branch:** codex/a-transport-acceptance from 7235e50. Reserved paths were
  A tests/network relay/contact/session scenes, check scripts, and proven fixes
  in A networking/simulation if tests expose them. Whole-UDP impairment will cover
  reliable control as well as snapshots. B diagnostics intent ca07c21 is acknowledged;
  diagnostic/public API semantics and B/model paths stay unchanged. Detailed intent:
  docs/coordination/A_TRANSPORT_ACCEPTANCE.md.

- **A transport progress:** whole-UDP relay and four-player lifecycle scenes now
  cover handshake retransmission, lobby/loadout, round reset, damage, reconnect
  and rematch through actual delayed/lossy ENet control traffic. Two demonstrated
  defects were fixed: local replay could cross walls, and remote countdown poses
  extrapolated stale falling velocity below the floor. Wall shape sweeps and
  phase-aware extrapolation stay in A simulation/networking; no arena/art edits.
  B's published rebinding d533032 and diagnostics intent ca07c21 are acknowledged.
  Protocol/build and public diagnostics remain mvp-ab-3/protocol 4 with cumulative
  node-lifetime counters. Full MVP regression passed at 0/80/150 ms injection,
  including the new whole-UDP four-client cases. Independent server plus four
  client processes also passed. Worst contact settling was 183.3 ms at 80 ms and
  216.7 ms at 150 ms; local automated evidence does not close human LAN acceptance.

- **A preceding mode increment:** codex/a-five-v-five from df509a0. Implement ten-player
  custom team lobbies, existing five-per-side spawn markers and 240-second rounds;
  wire the option through A's app host menu/CLI. Existing duel/2v2 and team view
  semantics remain intact. A reserves session/match/world and A app/test paths;
  B/modelling paths remain untouched. Intent and API details are in
  coordination/A_FIVE_V_FIVE.md. FFA remains a separate follow-up.

- **5v5 contract note for B:** build mvp-ab-4/protocol 4 accepts capacity 10 with
  mode 5v5. First-to-two and team IDs remain unchanged. Match-view round entries
  are now compact round/winner summaries; consume the reliable results event for
  aggregate participant data and `details.match.rounds[].participants`. Complete
  results also arrive on results-phase reconnect, deduplicated by match ID.
  The prior 32 KiB receive limit could drop ten-player results; the bounded limit
  is now 128 KiB, with detailed history sent once rather than on every heartbeat.
  Existing B-owned files are unchanged. Full regression passed, including ten-client
  profiles 0/80/150 and separate eleven-process and five-process startup checks.
  The final regression exposed cross-entity starvation in ordered snapshot
  transport; plain unreliable snapshots now use the existing per-entity tick
  guard. An adversarial raw-UDP test proves both the old failure and new behavior.
  No input-command ordering or B diagnostic-field semantics change.

- **A hosted duel intent (2026-09-20):** reserves deployment configuration, hosted acceptance harness and A client fixtures on codex/a-hosted-duel-deployment. External private 1v1 results/rematch validation is next; no B implementation or wire contract edits. See coordination/A_HOSTED_DUEL_DEPLOYMENT.md.

- **A reconnect intent (2026-09-20):** reserves MvpSession recovery, general menu composition, reconnect panel and independent network/menu fixtures on codex/a-reconnect-flow. Existing server damage retention and token semantics remain; no B combat/controls/garage changes. See coordination/A_RECONNECT_FLOW.md.

- **A HUD accessibility intent (2026-09-20):** reserves combat/round HUD, HUD preferences/settings and general settings composition on codex/a-hud-accessibility. Text scaling through150%, color presets/highcontrast; no B controls/camera/garage or wire edits. See coordination/A_HUD_ACCESSIBILITY.md.

- **A Linux hosting intent (2026-09-20):** reserves CI/container runtime acceptance on codex/a-linux-hosted-runtime. Exercise real Linux release worker plus private1v1 lifecycle inside production image; no B runtime or contracts changed. See coordination/A_LINUX_HOSTED_RUNTIME.md.

- **A shutdown diagnosis intent (2026-09-20):** reserves independent runtime-exit diagnostics and validation harnesses on codex/a-shutdown-diagnostics. Investigate reproducible GDScript teardown failure; no speculative B camera/drive/bot edits or gate relaxation. See coordination/A_SHUTDOWN_DIAGNOSTICS.md.

- **A shutdown findings (2026-09-20):** no B implementation edits. One stationary
  baseline bot reading public views reproduces the same native 0x547f2c shutdown
  fault; command processing and repeated replacement are not necessary. Removing
  the encoder's MvpBot type did not fix it and was reverted. Added an opt-in
  independent diagnostic fixture/runner and strengthened drive crash detection.
  Native crashes can return zero after PASS, so retain both exit and log checks.
  Root cause remains open; see the diagnostic note for all trial counts.

- **A general-menu accessibility intent (2026-09-20):** reserves A-owned general
  screens, results/game/reconnect panels and composition/settings on
  codex/a-menu-text-accessibility. Existing HUD text scale will also cover those
  general menus, with independent enlarged-layout tests. B garage/customisation
  and control panels remain B-owned; shared local MenuTextScale helper will be
  available for follow-up integration. No network/input schema changes. See
  coordination/A_MENU_TEXT_ACCESSIBILITY.md.

- **A general-menu accessibility handoff:** `HudPreferences.text_scale` now
  applies to A's general menus as well as the HUD without a file/schema migration.
  `MenuTextScale.apply(root, factor)` caches base fonts and covers option popups;
  individual `apply_text_scale` methods own reflow. B should adopt this in its
  garage/customisation/control-settings surfaces separately, with enlarged
  layout checks. A preview/cancel/save/new-screen propagation and independent
  menu/match/settings tests are included. No B implementation edits.

- **A world-marker intent (2026-09-20):** reserves a read-only 1v1/practice badge
  node, menu-game/accessibility composition and independent tests on
  codex/a-duel-world-markers. Consume published BotView presentation poses/team/
  elimination state. Preserve B paint/meshes, camera, controls and combat; no
  wire changes. See coordination/A_DUEL_WORLD_MARKERS.md.

- **A world-marker handoff:** `BotWorldMarkers` reads published `bot_views()`
  after presentation interpolation; local/practice identity does not use lobby
  slots or owner-ID ordering. Labels/stems are A-owned depth-tested geometry,
  leaving bot paint, meshes, camera and collision unchanged. OUT uses the
  authoritative elimination field and resets with the new-round view. Existing
  HUD text/palette/contrast settings apply. B may continue asset/control work
  without modifying this node; no new producer fields are required.

- **A continuous audio intent (2026-09-20):** reserves audio scripts, A session
  `audio_views()` accessor, menu-game composition and independent audio tests
  on `codex/a-spatial-gameplay-audio`. Reuse existing physical snapshot fields
  and weapon metadata, including practice targets; no B producer/wire changes.
  B can continue combat/drive/assets work. Details and planned validation:
  [audio coordination](coordination/A_SPATIAL_GAMEPLAY_AUDIO.md).

- **A continuous audio handoff:** `MvpSession.audio_views()` now publishes
  detached existing physical snapshot data plus displayed position. A's
  continuous audio consumes drive demand, grounded sideways velocity and
  weapon family/charge. Spinner coast-down is retained, saw power is binary,
  and hammer/lifter charge does not create fake rotor sound. No additional B
  producer fields or wire changes are required. B may continue its owned work;
  audio coverage and human listening polish remain A follow-ups.

- **A combat-status audio intent (2026-09-20):** reserves A audio scripts,
  menu-game composition and independent tests on `codex/a-combat-status-audio`.
  Uses existing BotView armor/charge/cooldown/state plus published weapon family;
  no B source or wire changes. Precise captions report full speed/charge/power
  or cooldown completion without duplicating attack eligibility rules. See
  [status-audio coordination](coordination/A_COMBAT_STATUS_AUDIO.md).

- **A combat-status audio handoff:** detector consumes existing accepted local
  BotView plus family metadata; spinner/lifter/saw/hammer captions describe
  observed states rather than promise an eligible attack. Armor breaches and
  simultaneous critical warnings use bounded sound/caption pools. A's caption
  layout was extended for combined warnings at enlarged text sizes. No B source,
  controls, combat rules, content IDs or wire schemas changed.

- **A impact/crowd audio intent (2026-09-20):** reserves A audio scripts,
  menu composition and independent fixtures on `codex/a-impact-crowd-audio`.
  Reuse existing combat-event world positions and match transitions for four
  fixed spatial impact voices and a bounded arena reaction. No invented
  material tags, B source changes or wire additions. See
  [impact/crowd coordination](coordination/A_IMPACT_CROWD_AUDIO.md).

- **A CI fixture intent (2026-09-20):** failed Windows run35503755098 exposed
  online-menu test HTTP binding failure, separate from the known native crash.
  A will repair temporary fixture port allocation and fail-fast diagnostics in
  its independent online-menu test/helper. No production service or B source
  changes. Keep native shutdown acceptance separate from this fixture repair.

- **A impact/crowd audio handoff:** accepted combat-event world positions now
  place four reused spatial impact voices; one additional crowd voice reacts to
  real round/match transitions. Engine capture verifies panning and distance
  attenuation. Captions/dedup and user bus settings are retained, and no B
  producer fields or material tags were added. Material-specific variation and
  human listening remain open. The separate HTTP fixture repair affects only
  A test infrastructure; production networking is unchanged.

- **A 1v1 Quick Play intent (2026-09-20):** reserves public service/client,
  original-theme online panel and independent/hosted fixtures on
  `codex/a-duel-quick-play`. Add isolated two-player queue with advertised
  capability; active client requests 1v1 explicitly. Expired guest state becomes
  cleanly retryable. No B runtime, controls, garage or wire changes. See
  [Quick Play coordination](coordination/A_DUEL_QUICK_PLAY.md).

- **A Fly deployment intent (2026-09-20):** user approved the recurring hosting
  cost. New app `battlebots-fumbleforce` runs one Stockholm Machine with dedicated
  IPv4. A validates public private/Quick Play duels before enabling the shared
  `project.godot` matchmaking URL. No input-action or B producer changes. See
  [live deployment](coordination/A_FLY_DUEL_LIVE.md).

- **A transport compatibility update:** measured Fly path drops at ENet's default
  packet size. A enables range-coder compression on both session ends and bumps
  build to `mvp-ab-12`; use matching clients/server. No B producers or protocol-4
  bot fields changed. Public validation evidence is tracked in the live handoff.

## B current recovery intent

codex/b-garage-recovery begins from e24ab02: explicit disk reload retains edited drafts; reviewed backup recovery preserves original files. Store/tests delegated; profile/UI owned by primary. See coordination/B_GARAGE_RECOVERY.md.

- **A live duel refinement intent:** add an A-owned held 1v1 scoreboard consuming
  the existing remappable `scoreboard` action. No B bindings/input collectors
  change. After integration, B can rename the stale "Scoreboard (planned)"
  settings label to "Scoreboard". Also align online/result labels and verify
  public reconnect independently; see
  [refinement coordination](coordination/A_LIVE_DUEL_REFINEMENT.md).

### A coordination — manual menu feedback, 2026-09-20
User requests prominent vehicle selection/switching instead of a dropdown and a real 3D active bot on a rotating pedestal instead of the static image. B owns implementation; A owns integration into general main/lobby flows. Please publish a reusable preview/selection interface and coordinate ready/loadout locking. A is fixing responsive menus, full-screen coverage, button emphasis, persistent lobby friend code and themed settings/video navigation. Controls/camera behavior remains B-owned. See coordination/A_PLAYTEST_MENU_FEEDBACK.md and A_MVP_TASKS.md for all seven open acceptance items.

A settings integration update: general Settings now opens a themed five-category hub; Camera/Controls consume B's existing transactions through A composition. The user explicitly rejects menu scrolling: Controls still has its internal binding list, so please provide paged/grouped binding presentation and preserve capture/cancel semantics. Main/lobby vehicle selection and automatic showcase remain open; A will consume the published GarageBotPreview API from 682824b. The held 1v1 scoreboard now consumes the existing action, so the old planned label can be removed by B.

## B text accessibility intent

codex/b-menu-text-accessibility begins from d6e154e: Garage/Customize/catalogue/recovery and camera/input settings consume MenuTextScale. Parallel ownership and the single coordinated menu_game propagation call are in coordination/B_MENU_TEXT_ACCESSIBILITY.md.


## B response to the no-scroll handoff

The text-accessibility branch now incorporates fe9f2f0: Garage/catalogue/Customize and recovery use pages, Controls uses Driving/Weapons/Camera & HUD groups, and Camera fits an inline form. Existing transactions work through A's themed hub. The Scoreboard label is no longer planned. Featured main/lobby vehicle selection and automatic showcase remain the next separate B implementation/A integration work.


- 2026-09-20 B: starting featured vehicle selection/rotating showcase on codex/b-featured-vehicle from 9e54dcc; see coordination/B_FEATURED_VEHICLE.md for component API, main/lobby boundary and checks.

- 2026-09-20 B delivery: FeaturedVehicle now serves main/lobby with named selection,
  canonical rotating assembly and Pause/Resume. Explicit lobby Apply, complete
  paint acknowledgement and phase/pending locks preserve authority. Static card
  and dropdown are removed. Independent/native long/invalid-build checks pass at
  720p/1080p/ultrawide through 150%; baseline and affected menu/preview regressions
  pass. See coordination/B_FEATURED_VEHICLE.md. Authored assets, unsaved-build test
  drive and remaining combat/control/hosted-1v1 acceptance remain open.

- 2026-09-20 B intent: direct unsaved-build Test Drive on codex/b-garage-test-drive from e0ce7c4; separate entry/menu_game integration avoids the active Sawblade/legs task. See coordination/B_GARAGE_TEST_DRIVE.md.

- 2026-09-20 B investigation: terrain-aware camera clearance on codex/b-terrain-camera, from f570bf9. Reproduce rolled-anchor overlap on Moon; camera-only scope avoids active Sawblade/legs work. See coordination/B_TERRAIN_CAMERA.md.

- **B camera mouse scaling:** investigate resolution-dependent orbit in B's input adapter on codex/b-camera-mouse-scale; independent engine event/adapter scene. No model/drive/weapon or network changes. See [scope](coordination/B_CAMERA_MOUSE_SCALE.md).

- 2026-09-20 B: Sawblade Tank runtime/garage integration reserved; optional cosmetics contract and acceptance in coordination/B_SAWBLADE_INTEGRATION.md.
- **B camera round lifecycle:** independent real-session camera/input continuity and rearming acceptance on codex/b-camera-round-lifecycle; no new spectator behavior or model/drive/weapon edits. See [scope](coordination/B_CAMERA_ROUND_LIFECYCLE.md).

- **B component damage intent:** localized snapshot-driven weapon/drive damage presentation on codex/b-component-damage rebased onto dfc7dd5. Cosmetic-only paths and independent acceptance in [scope](coordination/B_COMPONENT_DAMAGE.md).

- B component stages implemented: snapshot-driven weapon/drive overlays and bounded smoke; mapping, state and native MvpBot integration checks pass. See coordination/B_COMPONENT_DAMAGE.md. Sparks/fragments and human readability remain open.

- B user-requested HUD handoff: fixed green/red health bars under player identities,
  isolated BotWorldMarkers change coordinated with the other developer. Scope and
  acceptance: [player health bars](coordination/B_PLAYER_HEALTH_BARS.md).

## A coordination — Quick Play service sync, 20 September 2026
A is updating the existing hosted server to current main catalogue revision 6 and fixing online error visibility. Scope: online.gd, online panel checks, deployment evidence. No B implementation or shared protocol edits. See coordination/A_QUICK_PLAY_SERVICE_SYNC.md.

- B impact feedback resumed on `codex/b-impact-feedback`: confirmed-event sparks
  and bounded cosmetic fragments, independent rendering/event lifecycle scenes and
  narrow menu-game signal wiring. See [scope](coordination/B_IMPACT_FEEDBACK.md).

- B visual budget audit on `codex/b-visual-budget`: two/ten bot native load and all
  authored combination geometry/LOD inventory. See [scope](coordination/B_VISUAL_BUDGET.md).
