# B-06 — network diagnostics

Owner B; branch `codex/b-network-diagnostics`, stacked on B input/menu `d533032`
and A/B integration `bdb42ef`. Art branches remain separate.

## Intent published before implementation

B will add a read-only status/diagnostics panel to the existing preview using
SessionBotSource.session. No changes to A's app, session, transport or commands.
It will show connection state, client RTT/correction/interpolation and server
snapshot/rejection metrics where applicable, plus build/mode and local physics
timing in optional details. Missing values remain unavailable, never inferred good.

The panel sits in a separate presentation CanvasLayer, so A hiding the ordinary
preview HUD for its menu does not hide connection status. Camera/settings modals
hide it. Interacting with details releases gameplay input before button activation.
The panel never reconnects, changes readiness or sends commands itself.

A's diagnostics currently survive leave(). B will hide remote metrics outside an
active client match and label counters as cumulative over the session-node lifetime.
No simulated packet-loss metric or remote physics timing will be invented.

Independent evidence: widget scenarios (including malformed/degraded data), a
standalone B diagnostics scene, actual two-peer UDP session wiring, existing
presentation regressions and a rendered 1280x720 check. Two subagents own widget
and UDP-test work; B owns the adapter, standalone fixture, docs and combined review.

## Delivered evidence

Implemented the panel and preview adapter without editing A-owned runtime files.
DiagnosticsLayer is independent from the HUD layer; settings suppress the overlay.
Details releases input without temporarily stealing keyboard focus. At 1280x720
its paused position fits beside A's current 720px session menu with no overlap.
Fresh snapshots gate client values for each connection/match/phase transition.

All nine B presentation suites PASS. The live test uses real ENet peers, checks
exact session values, drops unreliable host traffic to produce real degraded
snapshots and restores it to verify recovery. Leave/rejoin/practice clear stale
remote values. Independent scenarios and A's actual menu were rendered/inspected.
A duel/menu and navigation regressions PASS; baseline check recorded at handoff.
Two subagents supplied widget validation and UDP integration coverage. The broad
B goal remains active: production lobby/HUD/garage, readability, release features
and two-computer acceptance are still open. This branch depends on input/menu
and does not imply main or A's integration branch already contains the changes.
Final baseline check: BASELINE PASS. A coordination log preserved unchanged.
