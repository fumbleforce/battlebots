# A — whole-transport and contact acceptance

Owner A; branch `codex/a-transport-acceptance`, based on contact/reconciliation
`7235e50` (mvp-ab-3, protocol 4). Modelling and B presentation branches stay separate.

## Intent before implementation

Add a test-only loopback UDP relay so delay, jitter, loss and duplication affect
the entire ENet transport, including handshake, baselines and reliable transitions.
Measure actual RTT; requested injected delay is not a claim about measured RTT.
Use real-time execution, because accelerated engine time distorts ENet throttling.

Independent work: one A subagent owns the relay fixture and raw-datagram test;
another owns a wall-contact scene. A owns session integration tests, any proven
production fixes, validation scripts and this handoff. No modelling, arena,
presentation, UI or input collector changes are planned.

Acceptance: reliable lobby/start/round/rematch/reconnect behavior under impaired
raw UDP; unchanged authority/ownership; clock estimates based on real delayed
control replies; wall-contact convergence and bounded poses. Retain the 80 ms
contact target and report failures rather than bypassing them. Human LAN/feel
acceptance remains open.

## Coordination with B

B's diagnostics intent at ca07c21 is acknowledged. Public session and diagnostic
field semantics stay unchanged in this increment; cumulative counters still last
for the session node lifetime. Preserve B's protocol/build display and input gate.
All relay instrumentation stays in A test paths and does not become a production
loss/latency metric. Follow-up status will be appended here and in the shared TODO.

## Defects reproduced during the increment

- Sustained north-wall drive: client replay crossed the wall while authority
  remained bounded (1.060 m peak presentation error). Static-world shape sweeps
  now constrain forward replay in the physics callback; first snapshots seed exact
  authoritative pose/velocity. Targeted wall rerun measured 0.014 m at North and
  0.010 m at the chamfer, with immediate settling after braking. Dynamic contacts
  and rotational sweeps remain approximate; this is not a Jolt rollback system.
- Four-client whole-UDP round reset: a remote presentation extrapolated a stale
  falling pose below the floor during countdown (presentation Y=0.039944 versus
  authority Y=0.25). Remote extrapolation now applies only to active, surviving
  bots; interpolation remains available during transitions. The independent
  regression failed before this fix and passes after it.
- The first transport fixture compared JSON-decoded numeric variants with their
  original integer variants; canonicalizing the expected wire value corrected
  that test assertion. This was not a dropped loadout request.

The relay drops the first client's first connection packet deliberately, then
uses seeded bidirectional delay/jitter/loss/duplication. Four-player admission,
loadout/readiness, damage, scoring, round reset, reconnect with token rotation,
and rematch are exercised through that same route. No production packet bypass
or test/debug RPC is introduced. Actual RTT is printed separately from injected
delay; an 80 ms injection measured roughly 118–135 ms in the initial active run,
with a reliable retry sample at 287 ms after reconnect.

The preceding contact increment 7235e50 passed CI validation, both exports, and
the separate-process server/four-client check (run 35459583307).

## Final local validation

Godot 4.7.2 stable, Jolt, Windows, Ryzen 9 9950X3D. Real-time network checks
preserve 60 Hz physics; pure physics tests retain accelerated execution.

- Full `tools/check-mvp.ps1`: PASS, including baseline/import, existing gameplay,
  UI integration, clocks, all three session/contact profiles, raw relay and new
  four-client whole-UDP profiles. Log: `%TEMP%/battlebots-transport-mvp.log`.
- Contact worst settling: 183.3 ms at 80 ms and 216.7 ms at 150 ms. Non-contact
  correction p95 at 80 ms: 0.137 m. Wall North/chamfer peaks in the full run:
  0.022/0.014 m, both with 0 ms post-brake settling and strict bounds passing.
- Whole-UDP measured RTT samples: 32–46 ms at zero injected delay; 119–151 ms at
  80 ms injection; 185–219 ms at 150 ms injection. Clock error never exceeded
  0.5 physics ticks in these sampled active/reconnect checks. All four players
  completed results/rematch; reconnect preserved entity, damage and token rotation.
- `tools/check-processes.ps1`: PASS, independent dedicated server plus four
  clients reached active. Log directory:
  `%TEMP%/battlebots-process-check-06bc4d3c30a949aeadd6678230758161`.
- `git diff --check`: PASS. No B/model paths changed; generated source UIDs included.

The raw fixture's seeded-burst test waits for end-to-end socket completion rather
than a fixed drain pause; a max-60 run exposed that initial test timing mistake.
Full rotational/dynamic contact rollback, a broader collision matrix, real LAN
playtesting and human camera/control feel remain outside this completed increment.
