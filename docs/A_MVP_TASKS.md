# Developer A MVP work

Owner: A. Playable branch: `codex/a-b-integration` at `bdb42ef`.
Active follow-up: `codex/a-contact-reconciliation`. B-owned files remain outside A work.

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
- [ ] Broaden collision/transport acceptance beyond the scripted scenarios; retain the 250 ms gate.
- [ ] Joint two-computer LAN/camera/control-feel acceptance (requires B's machine).

The final LAN and human-feel gate cannot be replaced by localhost tests. Record
actual measured outcomes and remaining gates in HANDOFF.md; do not mark them passed
without running them.
