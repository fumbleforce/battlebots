# Developer A MVP work

Owner: A — menus, networking, game rules, game world and audio. B owns combat,
bot models/weapons, bot-customisation menus and player controls. Earlier playable
checkpoint: `codex/a-b-integration` at `bdb42ef`.
Current integration: `ec3195e`, including hosted matchmaking and B's results menu.
User priority: actual playable 1v1/2v2 gameplay. Ten-player support, optimization
and acceptance are removed from the active todos. Existing implementation and
historical evidence remain; they do not create further ten-player work.

Acceptance: executable 2v2 authority/session, spinner/lifter combat, resources,
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
- [ ] Joint two-computer LAN/camera/control-feel acceptance (requires B's machine).

The final LAN and human-feel gate cannot be replaced by localhost tests. Record
actual measured outcomes and remaining gates in HANDOFF.md; do not mark them passed
without running them.

## Additional implemented gameplay and remaining services

- [x] Main menu/LAN flow and online-client integration; detailed results/rematch merged.
- [x] User-supplied menu melody integrated and included in playtest exports.
- [x] Arena/world integration, spawn lifecycle and authoritative match rules.
- [x] Four-to-eight-player FFA, elimination-tick placements and shared wins; historical implemented mode.
- [ ] General menu/HUD/tutorial polish and arena readability for playable small matches.
- [ ] Gameplay audio from authoritative combat/match events, coordinated with B's weapons.
- [ ] Public allocation/identity/result services, deployment and verified persistence.
  Hosted playtest increment `codex/a-hosted-matchmaking` adds guest identity,
  private codes, solo 2v2 queue, dedicated allocation and admission. Persistent
  accounts/results, parties, region/skill matching and release acceptance remain open.

Apply the user's current gameplay priority when ordering this work. Historical
ten-player targets in the original spec/handoffs are outside the active backlog.
Combat, drive/ground physics, bot assembly/catalogue, all five weapon families and
loadout persistence were implemented earlier; their maintenance now belongs to B.
A retains network prediction/integration and consumes B's public bot interfaces.
