# Worker B — shared task list

Worker B maintains this list after every increment. Worker A can use the IDs in
handoffs or PRs. Status describes B's branch, not what has been merged to main.
Nothing here implies A has already implemented a requested dependency.

**Current branch:** `codex/b-arena-camera` (camera baseline plus dependent UI work).
**Latest completed increment:** B-03, camera settings UI.
**Next increment:** B-04, input and menu polish.
**Integration reference:** [B handoff](DEVELOPER_B_HANDOFF.md).
**Working rules:** [ownership and workflow](TEAM_WORKFLOW.md).

## Done on B's branch

- [x] **B-01: Arena and third-person camera.** Floor, walls, chamfered corners,
  team/FFA spawns, camera collision, orbit/zoom/recenter, stable horizon, and mock
  camera test controls. Baseline and presentation tests passed. Ready for A to
  review wall collisions and camera feel with the real drive implementation.
- [x] **B-00: Visible cooperation plan.** This checklist records sequence, file
  ownership, completion criteria and dependency requests for A.
- [x] **B-02: Reusable status HUD.** Labelled core/battery/heat/charge bars and
  textual weapon/low-core/high-heat/elimination status using existing BotView.
  Invalid values are labelled, out-of-range values clamped for display, and missing
  targets clear stale information. Shared A/B scene checks and rendered tests passed;
  the layout was visually inspected at 1280 × 720. No shared API changes.
- [x] **B-03: Camera settings UI.** Live sensitivity, Y inversion, auto-recenter
  and strength controls with defaults, Save/Cancel and isolated local persistence.
  Opening the modal neutralizes gameplay input. Tests cover fresh-scene reload,
  replacing a saved file, cancel, invalid settings, failed saves and focus loss;
  the rendered 1280 × 720 panel was visually checked.

## Active and next — B can do these independently

- [ ] **B-04: Input and menu polish.** Keyboard navigation, reliable cursor
  capture, focus-loss behavior, and clear resume/return controls. Prepare rebinding
  UI against an agreed settings adapter; ask A for required InputMap changes.
  **Done when:** menus cannot accidentally drive or fire the bot and can be used
  without a mouse. Full rebinding waits for agreement on persistence ownership.
- [ ] **B-05: Arena readability pass.** Team identifiers that do not rely solely
  on color, clearer bot facing, restrained materials/lighting and spawn inspection
  helpers. **Done when:** players can distinguish facing and teams at follow-camera
  distance; decorative objects add no combat collision.

## Next integration checkpoint — A + B

- [ ] **AB-01: Real drive + B camera/HUD.** A exposes the real bot via the current
  BotSource contract. B connects presentation without editing A's drive logic.
  Together check acceleration, reverse steering, wall contact, flipping, recovery,
  camera jitter and component feedback on both office computers.
  **Needs from A:** a branch/commit ready to test; stable camera anchor; complete
  camera_exclusions RIDs; coherent BotView snapshots. No new contract is required
  for the initial core/resource bars.
  **Observed candidates:** origin/codex/a-drive-controller at `14236d2`, and
  origin/codex/a-mvp at `d61efc5`. Read-only inspection confirmed the current
  BotSource/BotView boundary remains compatible; combined-branch playtesting has
  not yet been performed. These are observed commits, not claims of A's approval.

## Waiting for A's interfaces — do not guess authoritative state

- [ ] **B-06: Network/debug overlay.** Display connection state, RTT and correction
  metrics. **Needs A:** read-only diagnostic fields/signals with units and update
  semantics. Use explicitly labelled fixtures until those exist.
- [ ] **B-07: Lobby and ready flow.** Slot/team/build validity views plus host,
  join, ready, leave and failure messages. **Needs A:** session request API and
  lobby-view contract; server remains responsible for readiness and transitions.
- [ ] **B-08: Match HUD/results/spectating.** Timer, round score, survivors,
  elimination/recovery messages and results. **Needs A:** authoritative match view,
  event IDs and bot states; B never infers winners from local health displays.
- [ ] **B-09: Garage preview and build UI.** Socket selection, part comparison,
  validation errors, save/load and test-drive. **Needs A:** registry, legal-loadout
  validator, derived stats and persistence API. Art/preview mocks can proceed first.

## Later B scope

- [ ] **B-10:** Weapon animation/audio/VFX using A's weapon state and impact events.
- [ ] **B-11:** Tutorial, accessibility settings, controller presentation and final UI.
- [ ] **B-12:** Optional first-person camera after third-person integration is stable.

## Coordination and editing boundaries

B is actively editing `scenes/ui/`, `scripts/ui/`, `scripts/presentation/`, B's
sandbox, B's fixtures/tests and B-owned documentation. A owns simulation, networking,
bot assembly, shared contracts, data, app bootstrap and project.godot. Ask before
changing the other owner's files; propose contract changes in a handoff first.

After each completed increment: update this list and the handoff, run relevant
checks, commit task files only, fetch/rebase onto origin/main, and push the task
branch. Preserve unrelated local edits. Rebasing/pushing a feature branch does
not merge it to main; A and B should review integration changes before merging.

## Latest handoff to A

- B-01 through B-03 are ready on this branch; B-04 is next.
- Continue drive/network work without editing B's UI/camera scenes.
- No engine settings or new input actions are requested through B-03.
- Camera preferences use user://presentation_camera.cfg and a B-owned adapter;
  this does not replace A's future profile/settings service. Coordinate migration
  before moving these settings into shared persistence.
- A's drive/MVP branches are now visible remotely. Agree the integration candidate
  before joint playtesting. This checklist is a repository handoff, not a sent message.

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
