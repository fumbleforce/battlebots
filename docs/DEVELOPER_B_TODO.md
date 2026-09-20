# Worker B — shared task list

B maintains the sections above A's coordination log. Completed task branches
must now merge into main, which is the shared latest game. Historical branch
entries retain their original validation and do not claim every release gate passed.

**Current ownership:** B owns combat, bot assets/models/weapons, bot-customisation
menus and player controls. A owns other menus, networking, game rules, game world
and audio. Historical labels below describe authorship, not current ownership.

**Latest published B branch:** `codex/b-results-followup`, based on integrated A `3f0e80f`.
**Latest increment:** Detailed final/per-round results, FFA placements and rematch in the default menu shell. See [results follow-up](coordination/B_RESULTS_FOLLOWUP.md).
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

User priority update (2026-09-20): a fully working 1v1 game comes first. Defer
2v2, FFA and other multiplayer modes, plus all tutorial work, until then. A owns
the raised HUD priority and external matchmaker/server deployment; B supplies
combat/bot state and feedback through the shared interfaces.

A also prioritizes general menu refinement, especially integrating multiplayer
and networking screens with the original menu system's design and navigation
(user feedback, 2026-09-20). B retains garage/customisation ownership.

- [ ] **Combat and bots:** Maintain damage/resources/recovery, weapon mechanics
  and visuals, bot assembly/catalogue and model integration. Investigate combat
  defects handed off by A's network/match-flow checks.
- [ ] **Controls and camera:** Player input/driving, camera and spectator control
  behavior, including control-specific settings. Consume A's match phase and
  spectator sources; do not calculate local winners or ready state.
- [ ] **B-09: Full garage.** Supplied kit now edits/saves canonical builds with validation and paint. Remaining: live 3D preview, undo/redo, detailed before/after comparisons and full repair UX. APIs: ContentRegistry.validate/starter and
  LoadoutStore.save/load_saved; preview unsaved builds, show specific validation
  reasons, preserve invalid builds for repair. These APIs are available now.

## Later B scope and acceptance still open

- [ ] **B-10:** Weapon animation/VFX from authoritative state/events. A owns audio.
  Sawblade-tank art is separately published on `codex/b-sawblade-tank`; it is not
  a dependency of the input/menu branch. Primitive spinner/lifter visuals already
  exist in the integration; bot assembly now belongs to B. Coordinate shared
  content identity and network-state changes with A.
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
A feature-branch push does not merge into main. Review against the declared
integration base, not the still-old main branch.

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
