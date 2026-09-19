## Developer A coordination — 19 September (codex/a-mvp)

This section is maintained by A. B's sections above were copied unchanged from
`origin/codex/b-arena-camera` at `40aa6b1`; their status still describes B's branch.
Please preserve this section when integrating. A's detailed acceptance tracker is
[A_MVP_TASKS.md](A_MVP_TASKS.md). A will fetch/check this list each increment.

- **A-01 DONE / AB-01 available:** drive implementation is pushed at `14236d2`
  on `codex/a-drive-controller`. BotSource/view/anchor/exclusions remain stable.
  A's sandbox again instances the shared `Preview`; B owns its input/camera.
  A's fallback walls are skipped when B's `Arena/Walls` exists. An isolated checkout
  combining A with B at `40aa6b1` passes B's camera/arena and camera-settings tests.
  This verifies scene compatibility; the joint human playtest is still pending.
- **A-02 DONE / B-09 available:** catalogue/validation/store at `d61efc5` on
  `codex/a-mvp`. `ContentRegistry.starter/validate`, `LoadoutValidation` and
  `LoadoutStore.save/load_saved` are usable now. Save schema 1, max 12 builds,
  canonical JSON in `data/mvp_parts.json`. Weapon scope is spinner + lifter.
- **A-03 IMPLEMENTED / TESTED:** pure combat and 2v2 rules, physical assembly,
  damage queries and recovery torque. Headless spinner-hit/cadence/ally-immunity,
  reset/wreck/assembly checks and drive regressions pass. Physical lifter/recovery
  feel remains an integration gate. Own `scripts/simulation`, `scripts/weapons`,
  `scenes/bots`, and `tests/simulation`. Preserve existing BotView fields; add
  defaulted optional fields so B's mock remains a compatibility adapter.
- **A-04 SESSION TESTED / B-06–08 AVAILABLE:** ENet session with host/join/leave/ready requests,
  authoritative lobby/match/bot views, event IDs, diagnostics, reconnect and
  prediction. Own `scripts/networking`, `scripts/services`, `scripts/core` and
  isolated network tests. Exact API is in CONTRACTS. Four real UDP peers complete
  ready/loading/rounds/results/rematch; token reconnect preserves damage. Maximum
  observed per-entity snapshot is now 420 bytes (protocol 3). Shared-model local
  prediction/reconciliation and remote interpolation are implemented. Application
  impairment profiles at 80/150 ms pass; 80 ms non-contact correction p95 is
  0.145 m. Joint LAN/contact/camera feel is not yet accepted. B should consume
  camera_anchor() rather than its internal path, now on a separate visual root.
- **A-05 IMPLEMENTED / TESTED:** app wiring, export presets and CI/check tools.
  `scenes/app/mvp.tscn` is A's temporary integration console, not production UI.
  `SessionBotSource` lets B's existing adapter forward local commands through the
  session and follow the current bot across loading/reconnect. Windows client and
  Linux server exports build; headless pack/client runs pass. Four independent
  client processes reach active with a dedicated server. A will not edit
  B's camera/UI/input/settings/arena/fixtures. B's B-03 settings file can remain
  independent; no competing settings global is planned for this MVP increment.
- **Still joint:** LAN on both computers and real control/camera feel. A's
  localhost/headless checks will be reported separately from those acceptance gates.
- **B-04 integration request:** A's charged lifter fires on intentional LMB release.
  When menus/focus loss suppress input, please set neutral command `brake=true`
  and `secondary_held=true` (lower/cancel), including disabled-control physics ticks.
  An all-false command means a normal release, not a cancellation. A's timeout path
  already cancels safely. B owns this adapter change; A has not edited it.
- **B-08 available:** `session.spectator_sources()` returns surviving teammate
  BotSources. Preserve normal camera boundaries when cycling them.
- **A validation:** ba4b90a CI succeeded (checks, both exports, five processes).
  Added hostile session/old-token tests, physical pin cancellation, and ten-body
  headless stress measurement (~0.83 ms frame p95 on Ryzen 9 9950X3D). A's
  collision fixture now matches B's published chamfer planes at (+/-24,+/-24).


## A+B integration checkpoint — A owns codex/a-b-integration

- Published B-01–03 at 40aa6b1 are being combined with A at 759041e.
- A reserves scenes/app, scripts/core, scripts/networking, scripts/simulation,
  tests/integration, tools and the shared handoff. B's published files are imported
  unchanged. B can continue B-04 onward on its own branch.
- First acceptance: both existing suites pass together. Next: mount B's arena,
  orbit camera, HUD and settings through A's app/session adapter, with one collision
  arena and one input producer. Exercise practice/reset and four-client sessions.
- B-06–09 screens are not published yet. A will retain its integration console for
  session requests while exposing B's existing components; no replacement garage
  or production lobby is being authored in B's paths.
- Two-computer LAN and subjective feel remain pending access to the second host.

- Combined baseline, drive, content, rules, combat, stress and 0/80/150 ms network checks pass; B camera/arena and settings checks also pass.

- INTEGRATED: B arena/spawns, orbit camera, live resource HUD and settings now mount
  through A's app; one collision arena, one input producer. SessionBotSource's
  optional gate cancels suppressed lifter input without modifying B's adapter.
- PASS: app reset/camera/HUD/cancel checks, four UDP presentation clients and five
  independent processes. Build mvp-ab-1; protocol remains 3. Rendered practice opens.
- User requested simple weapon visuals and simpler menus. A reserves bot assembly
  and scenes/app for these small placeholders; B's camera/UI source stays intact.
- SIMPLE VISUALS/MENUS IMPLEMENTED: A-owned scenes/bots/weapon_visual.gd provides
  cosmetic spinner teeth/disc and lifter forks driven by BotView; no extra collision.
  A's app main/session menus now offer Practice/Multiplayer, builds and session flow.
  These are small integration placeholders; B's published files remain unchanged.
- Combined automated suite passes after these changes. Final graphical inspection
  stopped when the user pressed Escape to stop Computer Use; two-machine LAN and
  subjective feel remain pending. Updated graphical build is launched locally.
- LAN USABILITY: A's app shows host IPv4 candidates/port, starts Join blank, gives
  four-client/two-per-PC instructions, rejects blank joins without leaving, and
  honors custom CLI ports. Menu scrolls when lobby details grow. Baseline/app and
  four-peer presentation tests pass. B's owned files are still unchanged.
- IN PROGRESS (user-requested): A adds selectable 2-player 1v1 / 4-player 2v2
  hosting and state-specific app actions. Default UI choice will be 2 players.
  A reserves mvp_session, app bootstrap, integration tests and shared contracts;
  B's presentation/UI files remain unchanged. Host capacity drives readiness,
  team limits, loading and rematch; tests will cover both counts and menu phases.
- DONE: selectable 2-player 1v1 (app default) / 4-player 2v2. One window per person.
  API host(port, listen, player_count=4) is backward-compatible; lobby capacity/mode
  are authoritative. Build mvp-ab-2 requires both computers to update.
- DONE: setup, connecting, lobby, practice, live match and results show only valid
  actions. Ready toggles from server state; builds lock after lobby. B's duplicate
  preview hints are hidden by A's app while its menu is open, without editing B files.
- PASS: two-player real-UDP full match/rematch plus button-state and count guards;
  existing four-player 0/80/150ms suite and five-process check. Setup/lobby/practice
  were rendered and visually inspected at 1280x720. Cross-machine LAN remains pending.
- ROUND-END/ESCAPE FIX: reproduced baseline_preview.gd:112 null viewport by pressing
  Escape with released controls. The development preview removed the live scene
  before its final input call. A's app now consumes Escape first and toggles its
  menu; only explicit Main menu leaves, via a deferred, idempotent transition.
  B's files remain unchanged. B should also make standalone preview exit deferred
  and consume input before changing scenes when updating its own sandbox adapter.
- Regression coverage: real input dispatch after host/client round end and results,
  normal menu/settings Escape, and explicit current-scene replacement/cleanup.

