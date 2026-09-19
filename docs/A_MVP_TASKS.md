# Developer A MVP work

Owner: A. Branch: `codex/a-mvp`, based on local drive commit `14236d2`
(baseline `60feafe`). B-owned files remain outside this task.

Acceptance: executable 2v2 authority/session, spinner/lifter combat, resources,
recovery/elimination/judging, reconnect/rematch, canonical loadouts and persistence,
client prediction/snapshots, and documented APIs for B. Primitive bot visuals and
isolated A test fixtures are intentional. Full 5v5/FFA and remaining three weapon
families are phase 4, not MVP; public account/allocation services are phase 5.

- [x] Drive foundation and ground contact; regression tests.
- [ ] Canonical MVP catalogue, typed validation, assembly, versioned saves/migration.
- [ ] Damage zones, spinner/lifter, battery/heat, recovery, elimination and pins.
- [ ] 2v2 lifecycle, readiness, judging, simultaneous wipes, rematch and results.
- [ ] ENet host/join/leave, ownership/input validation, baseline and snapshots.
- [ ] Local prediction, remote smoothing, reconnect and disconnect timeout.
- [ ] Headless/graphical bootstrap, exports/CI checks and B API handoff.
- [ ] Automated pure/physics/four-peer integration and hostile-input tests.
- [ ] Joint two-computer LAN/camera/control-feel acceptance (requires B's machine).

The final LAN and human-feel gate cannot be replaced by localhost tests. Record
actual measured outcomes and remaining gates in HANDOFF.md; do not mark them passed
without running them.
