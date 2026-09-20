# Developer A MVP work

Owner: A — menus, networking, game rules, game world and audio. B owns combat,
bot models/weapons, bot-customisation menus and player controls. Earlier playable
checkpoint: `codex/a-b-integration` at `bdb42ef`.
Shared main includes hosted matchmaking source, natural-duel validation, gameplay
audio, practice, Foundry and the menu panels published as `1a5d38a`. Completed
increments push main directly; current priorities and acceptance are recorded below.
User priority (2026-09-20): finish a fully working 1v1 game first. Defer 2v2,
FFA and all other multiplayer modes until that is done. Defer the tutorial too.
Existing mode implementations and historical evidence remain, but do not create
active expansion or acceptance work.

## Highest-priority active work

- [ ] Complete the end-to-end 1v1 game: online entry, combat, round completion,
  results and rematch, with clear feedback and reliable recovery/reconnect.
- [ ] Finish presentation refinement across multiplayer/networking menus, the
  win screen, score screen and in-game menu (A, high priority). The user requests
  these pages as part of a complete 1v1 game, with the game menu consistent with
  the other panels. Existing implemented pages below are the starting point;
  retain an open polish task for consistent original-theme layout, styling,
  navigation and clear win/score/rematch/return actions throughout the full flow.
  Automated implementation checks do not close this remaining design feedback.
- [x] Expose same-session reconnect in the game menus, with bounded retry,
  damage/identity retention, results recovery and explicit leave. Independent
  ENet and composed-game checks pass; see [recovery evidence](coordination/A_RECONNECT_FLOW.md).
  External hosting and human recovery acceptance remain open.
- [ ] Deploy the externally hosted matchmaker and dedicated game server for 1v1;
  verify external connectivity and complete a real hosted duel through rematch.
  Existing private-duel support is the starting point; the current 2v2 queue is
  not the active delivery target. Public hosting remains outstanding. The
  [external duel harness](coordination/A_HOSTED_DUEL_DEPLOYMENT.md) now checks
  authoritative results and rematch as well as assigned connectivity; local
  validation does not close this deployment task.
- [x] Run private 1v1 through the production Linux container's real release worker,
  including results/rematch. [Linux CI evidence](coordination/A_LINUX_HOSTED_RUNTIME.md)
  closes the runtime packaging gap, not external deployment.
- [ ] Resolve the intermittent Windows native shutdown crash. CI and local runs
  reproduced `0xC0000005` after DRIVE PASS. Windows run35502338810 at35ef6a6
  subsequently passed the full workflow; one clean run does not establish a fix.
  [Bounded diagnostics](coordination/A_SHUTDOWN_DIAGNOSTICS.md) also reproduce it
  locally; the drive gate rejects native crash text even when the exit code is zero.
- [x] Prioritize the 1v1 HUD: readable combat/resource/weapon feedback, round
  state, timer, outcomes and rematch flow. A owns HUD presentation and consumes
  B's authoritative combat/bot interfaces. Core HUD, raw component diagram,
  recovery/immobilization, heading and duel survival status are implemented;
  [HUD evidence](coordination/A_DUEL_HUD.md) records scope and remaining limits.
- [x] Independent combat/round HUD text sizes through 150%, color-vision presets
  and high-contrast panels, saved through general Settings. Enlarged practice
  readout/captions and original-theme settings sample are included; see
  [accessibility evidence](coordination/A_HUD_ACCESSIBILITY.md).
- [x] Extend text sizes through 150% to A's general menus, online/lobby/loading,
  game/results/reconnect and audio/accessibility panels, with saved preview/cancel
  behavior and keyboard-accessible scrolling. See
  [general-menu evidence](coordination/A_MENU_TEXT_ACCESSIBILITY.md).
- [x] Add 1v1/practice world identification with distinct symbols/text, OUT state,
  color presets and high contrast. Depth-tested badges follow published poses
  and hide with menus/recovery; see [marker evidence](coordination/A_DUEL_WORLD_MARKERS.md).
- [ ] Remaining accessibility and communication: B-owned garage/customisation/
  control-settings text scaling to complete coverage throughout all menus,
  human world/team marker recognition and color-vision acceptance; ping
  presentation after the coordinated input/network interfaces exist.
- [x] Refine the general menus, especially multiplayer/networking screens (A).
  User feedback (2026-09-20): these screens are poorly integrated into the
  original menu system. Make online entry, host/join, connection progress,
  errors/retry/cancel and lobby transitions consistent with its visual design,
  layout and navigation. Treat this as high-priority 1v1 completion work alongside
  hosting and HUD. Original-theme online/private-duel, labelled direct host/join
  and connected lobby now pass rendered and real-session checks; see
  [menu-panel evidence](coordination/A_DUEL_MENU_PANELS.md). Human design review
  remains welcome and does not certify hosted deployment.
- [x] Add finished win and score screens for 1v1 (A), using authoritative match
  outcomes and scores with clear rematch/return actions; the menu-panel increment
  adds overview and score-detail pages to the existing results foundation.
- [x] Add an in-game menu page consistent with the design of the other panels
  (A), including coherent layout, styling and navigation. Validate it alongside
  the win/score screens as part of the complete 1v1 flow.
- [x] Human multiplayer playtest through a tunnel succeeded, as reported by the
  user on 2026-09-20. This records human play evidence, not external-hosting
  acceptance or measured camera/contact/network thresholds.

## Implemented foundation and remaining validation

Active acceptance: executable 1v1 authority/session, combat, resources,
recovery/elimination/judging, reconnect/rematch, canonical loadouts and persistence,
client prediction/snapshots, and documented APIs for B. Primitive bot visuals and
isolated A test fixtures are intentional. Prioritize combat, weapon feedback,
round completion, rematch and easy online play over population scaling.

- [x] 2v2 lifecycle, readiness, judging, simultaneous wipes, rematch and results.
- [x] ENet host/join/leave, ownership/input validation, baseline and snapshots.
- [x] Local prediction, remote smoothing, reconnect and disconnect timeout.
- [x] Headless/graphical bootstrap, exports/CI checks and B API handoff.
- [x] Automated pure/physics/four-peer integration and hostile-input tests.
- [x] Airborne replay tracks real Jolt gravity/rotation over the 250 ms replay window.
- [x] Measure scripted contact/flip/recovery prediction settling at 0/80/150 ms in independent scenes.
- [x] Four-client lifecycle/reconnect/rematch under whole-UDP impairment, including reliable control and lost initial connect packet.
- [x] Sustained wall/chamfer collision bounds and settling; inactive/eliminated remote extrapolation regression.
- [x] Reliable match transitions and one-second state recovery under total unreliable-snapshot loss; independent actual-ENet regression.
- [ ] Broaden collision/transport acceptance beyond the scripted scenarios; retain the 250 ms gate.
- [ ] Diagnose intermittent CI observer convergence failure (FFA damage in 35466215676) when relevant to gameplay work. Existing strict tests remain.

Human multiplayer is no longer an unperformed gate: the user reports successful
tunnel play. Specific unmeasured feel/transport checks remain separate; hosted
internet acceptance must still be performed after deployment.

## Additional implemented gameplay and remaining services

- [x] Main menu/LAN flow and online-client integration; detailed results/rematch merged.
- [x] User-supplied menu melody integrated and included in playtest exports.
- [x] Arena/world integration, spawn lifecycle and authoritative match rules.
- [x] Four-to-eight-player FFA, elimination-tick placements and shared wins; historical implemented mode.
- [ ] Arena readability for 1v1; menu refinement and HUD are prioritized above.
- [x] Practice target damage/knockout readout and direct restart with both bots repaired.
- [x] First-pass impact/round/warning/recovery audio from authoritative events,
  with captions and saved master/music/effects/announcement volume and mute.
- [x] First-pass 1v1/practice spatial drive, grounded sliding, spinner/saw and
  arena sound layers from authoritative data, with stale-source silence and
  local ambience ducking for warnings. See [audio evidence](coordination/A_SPATIAL_GAMEPLAY_AUDIO.md).
- [x] First-pass weapon status/armor-break cues with precise captions, accepted
  local baselines, bounded concurrent critical warnings and enlarged caption
  layout. See [status-audio evidence](coordination/A_COMBAT_STATUS_AUDIO.md).
- [ ] Finish audio coverage and listening polish: crowd cues, spatial impact
  mix, material variation and human listening acceptance.
  Current sliding audio approximates grounded sideways motion; it is not a
  measured tire-slip simulation. Hammer/lifter have no continuous rotor sound.
- [ ] Public allocation/identity/result services, deployment and verified persistence.
  Hosted playtest increment `codex/a-hosted-matchmaking` adds guest identity,
  private codes, solo 2v2 queue, dedicated allocation and admission. Persistent
  accounts/results, parties, region/skill matching and release acceptance remain open.

Apply the user's current gameplay priority when ordering this work. Historical
multi-mode targets in the original spec/handoffs are outside the active backlog.
Combat, drive/ground physics, bot assembly/catalogue, all five weapon families and
loadout persistence were implemented earlier; their maintenance now belongs to B.
A retains network prediction/integration and consumes B's public bot interfaces.

## Deferred until the 1v1 game is fully working

- [ ] 2v2, FFA and other multiplayer-mode development and acceptance, including
  the existing 2v2 matchmaking queue. Ten-player optimization/soak stays deferred.
- [ ] Tutorial: B owns control exercises and progression; A integrates its menu
  entry when this deferred work resumes.
