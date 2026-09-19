# Worker B — shared task list

B maintains the sections above A's coordination log. Status describes published
feature branches, not a claim that main contains them or that all release gates pass.

**Active branch:** `codex/b-match-hud`, stacked on playable lobby `eea0bb2`; runtime base A/B `bdb42ef`.
**Latest increment:** B-08a: authoritative match clock, scores and outcomes in the arena; 15 presentation checks pass.
**Next:** Results actions/statistics and spectating; coordinate mounting B frontend in A's F5 shell.
**Intent and evidence:** [B-08 coordination](coordination/B_MATCH_HUD.md).
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
- [x] **AB-01 automated compatibility:** Published A/B integration mounts the real
  session through BotSource with B arena/camera/HUD. This is not human LAN acceptance.

## Active and next — B-owned

- [ ] **B-05: Arena readability.** Color-independent team markers, bot facing,
  restrained materials and spawn inspection; decorative geometry adds no collision.
- [ ] **B-07 integration:** Playable B scene and reusable panel/adapter are implemented. A must mount them in the F5 app, replacing its integration menu. Full 5v5/FFA/public services remain unavailable in the current backend.
  **Original scope:** Use existing host/join/leave/team/ready/loadout
  requests and lobby_changed. Respect authoritative phase/capacity. A's current
  app menus are integration UI; coordinate replacing their presentation so there
  is one input producer and one lifecycle owner.
- [ ] **B-08: Match HUD, results and spectating.** Consume match_changed,
  bot_updated, combat_event, BotView's zones/timers and spectator_sources().
  No local winner calculation or inferred ready state.
- [ ] **B-09: Garage.** Consume ContentRegistry.validate/starter and
  LoadoutStore.save/load_saved; preview unsaved builds, show specific validation
  reasons, preserve invalid builds for repair. These APIs are available now.

## Later B scope and acceptance still open

- [ ] **B-10:** Weapon animation/audio/VFX from authoritative state/events.
  Sawblade-tank art is separately published on `codex/b-sawblade-tank`; it is not
  a dependency of the input/menu branch. Primitive spinner/lifter visuals already
  exist in A's integration, so replace them through a coordinated assembly change.
- [ ] **B-11:** Tutorial, accessibility, controller presentation and final UI.
- [ ] **B-12:** Optional first-person camera after third-person feel is accepted.
- [ ] **AB-02:** Two-computer LAN and human contact/camera/lifter/recovery playtest.
  Automated localhost/impairment coverage is not evidence for this acceptance gate.
- [ ] **Release:** Full 5v5/FFA presentation, remaining weapon families and full
  game-spec coverage. MVP 1v1/2v2 support does not satisfy the whole game spec.

## Editing and branch boundaries

B owns UI, input/camera presentation, arena/assets, B dev scenes/fixtures/tests and
B docs. A owns app bootstrap, session/core/simulation/bot assembly and integration
tests. Shared APIs stay compatible unless a coordinated contract change says otherwise.

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

- **A next mode increment:** `codex/a-ffa` from `e118f91`; intent and planned
  contracts are in [FFA coordination](coordination/A_FFA.md). A reserves session,
  MatchState, spawn selection, A app and independent tests. FFA uses unique entity
  teams and explicit placement/shared-winner results. B/model files remain untouched.
  B's observed match HUD `d983612` and results intent `0f343f7` are acknowledged,
  not imported. The results event remains the detailed-stat source; on FFA it now
  also carries `match.winners` and `match.placements`. A's shell remains separate
  until an explicit integration checkpoint preserves B's final UI and input owner.

- **Playable checkpoint:** codex/a-b-integration at bdb42ef; CI passed. Includes
  2-player 1v1 / 4-player 2v2, session-specific menu actions and the Escape fix.
  Build mvp-ab-2, protocol 3. Both peers must run matching builds.
- **Active branch:** codex/a-ffa, based on 5v5 e118f91 and transport fix df509a0
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

- **A current mode increment:** codex/a-five-v-five from df509a0. Implement ten-player
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
