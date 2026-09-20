# Developer A MVP work

Owner: A — menus, networking, game rules, game world and audio. B owns combat,
bot models/weapons, bot-customisation menus and player controls. Earlier playable
checkpoint: `codex/a-b-integration` at `bdb42ef`.
Current shared baseline: `6ff5c89` on main, including hosted matchmaking source,
B's results menu, natural-duel validation, gameplay audio, practice and Foundry. Completed increments
push main directly.
User priority (2026-09-20): finish a fully working 1v1 game first. Defer 2v2,
FFA and all other multiplayer modes until that is done. Defer the tutorial too.
Existing mode implementations and historical evidence remain, but do not create
active expansion or acceptance work.

## Highest-priority active work

- [ ] Complete the end-to-end 1v1 game: online entry, combat, round completion,
  results and rematch, with clear feedback and reliable recovery/reconnect.
- [ ] Deploy the externally hosted matchmaker and dedicated game server for 1v1;
  verify external connectivity and complete a real hosted duel through rematch.
  Existing private-duel support is the starting point; the current 2v2 queue is
  not the active delivery target. Public hosting remains outstanding.
- [ ] Prioritize the 1v1 HUD: readable combat/resource/weapon feedback, round
  state, timer, outcomes and rematch flow. A owns HUD presentation and consumes
  B's authoritative combat/bot interfaces.
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
  outcomes and scores with clear rematch/return actions. Existing results code
  is a foundation, not completion of these user-requested screens.
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
- [ ] Drive/skid/spin/arena sound layers, spatial mix and human listening polish.
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
