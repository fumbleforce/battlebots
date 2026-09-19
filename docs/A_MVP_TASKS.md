# Developer A MVP work

Owner: A. Earlier playable checkpoint: `codex/a-b-integration` at `bdb42ef`.
Current combined playtest: `codex/a-b-playtest`, with FFA `b71cb9b` and B's published
menu/controls/art branches. `codex/a-menu-flow` updates navigation and the playtest
export; the user requested resuming remaining spec work after that export is ready.

Acceptance: executable 2v2 authority/session, spinner/lifter combat, resources,
recovery/elimination/judging, reconnect/rematch, canonical loadouts and persistence,
client prediction/snapshots, and documented APIs for B. Primitive bot visuals and
isolated A test fixtures are intentional. Full 5v5/FFA and remaining three weapon
families are phase 4, not MVP; public account/allocation services are phase 5.

- [x] Drive foundation and ground contact; regression tests.
- [x] Canonical MVP catalogue, typed validation, assembly, versioned saves/migration.
- [x] Damage zones, spinner/lifter, battery/heat, recovery, elimination and pins.
- [x] 2v2 lifecycle, readiness, judging, simultaneous wipes, rematch and results.
- [x] ENet host/join/leave, ownership/input validation, baseline and snapshots.
- [x] Local prediction, remote smoothing, reconnect and disconnect timeout.
- [x] Headless/graphical bootstrap, exports/CI checks and B API handoff.
- [x] Automated pure/physics/four-peer integration and hostile-input tests.
- [x] Airborne replay tracks real Jolt gravity/rotation over the 250 ms replay window.
- [x] Measure scripted contact/flip/recovery prediction settling at 0/80/150 ms in independent scenes.
- [x] Four-client lifecycle/reconnect/rematch under whole-UDP impairment, including reliable control and lost initial connect packet.
- [x] Sustained wall/chamfer collision bounds and settling; inactive/eliminated remote extrapolation regression.
- [ ] Broaden collision/transport acceptance beyond the scripted scenarios; retain the 250 ms gate.
- [ ] Joint two-computer LAN/camera/control-feel acceptance (requires B's machine).

The final LAN and human-feel gate cannot be replaced by localhost tests. Record
actual measured outcomes and remaining gates in HANDOFF.md; do not mark them passed
without running them.

## Full-spec A work after the MVP

- [x] Ten-player 5v5 authority/session and 240-second rounds; impaired-session and independent-process checks pass.
- [x] Four-to-eight-player FFA, elimination-tick placements and shared wins; independent rules/session/menu checks pass.
- [x] Horizontal spinner with server-owned swept side contact, recoil and independent state/physics/ENet checks.
- [ ] Hammer and saw mechanics with server-owned stats/hits.
- [ ] Ten-player combat/performance/bandwidth and sustained soak acceptance.
- [ ] Public allocation/identity/result services, deployment and verified persistence.

These remain part of A's goal. The MVP checklist does not redefine the complete
requested game. Final art, menu/garage UX, accessibility and camera work belong to B.
