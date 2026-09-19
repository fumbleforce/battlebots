# A performance and reliability increment

Owner: Developer A. Branch: `codex/a-performance`, based on saw `5d3fd30`.
Reserved: independent performance scripts/scenes, process runner, network
regression fixtures and proven networking fixes. B's production assets/UI and modelling
checkout remain untouched. Build mvp-ab-9 keeps protocol 4/catalogue revision four.

Build a dedicated-server plus ten independent client process harness with all
five weapons, real commands/combat, normal match results and rematches. Measure
named CPU, server physics cost/throughput, per-player UDP traffic with overhead,
loading and process memory after warm-up. Short smoke runs validate the harness;
only a full 60-minute measured run can support the memory-soak gate. Headless
results cannot certify 1080p rendered performance or visual-effects budgets.

Targets: 60 Hz server, simulation p95 <12 ms; each player <100 KB/s down and
<30 KB/s up; arena load <10 seconds after preparation; no sustained >5% memory
growth across 60 measured minutes. Record sampling definitions and limitations.
Keep existing strict FFA observer-health and 5v5 rematch spawn assertions while
investigating their intermittent CI failures with captured diagnostics.

Process fixtures communicate only test lifecycle signals through a dedicated
temporary output directory. Gameplay uses the actual ENet session API. No health
restoration, invulnerability or shortened production match timers certify a soak.

## Reproduced state-recovery defect

Under total unreliable-snapshot loss, reliable round-two countdown arrived while
observers retained round-one health and epoch. A real two-client ENet scene fails
before the repair and passes after it. Match transitions now include bot state;
the existing one-second active/countdown heartbeat also repairs starved snapshots.
This does not recreate client worlds or reset input queues on ordinary heartbeats.
Delayed checkpoints use the existing tick guard; steady results/intermission
heartbeats omit repeated bot snapshots. The reset, repaired health/components,
elimination, settled spawns and later fast-stream recovery pass with snapshot
loss held at 100%. A ten-player profile-zero run and detailed results checks pass.
Detailed results are 56,572 bytes; steady results heartbeat 708 bytes, within the
existing 128 KiB and 4 KiB gates respectively. This proves a repairable gap, not
that the two earlier CI failures had precisely the same cause.

Combat events now identify `kind` as a canonical weapon or `ram`; measuring
weapon coverage from the attacker's equipped part alone incorrectly counts rams.

## Measurement boundaries

The server fixture times every actual MvpSession physics callback, including
simulation queries, match logic and network serialization. That wall time excludes
Jolt's engine step. Godot's TIME_PHYSICS_PROCESS monitor publishes roughly
one-second maxima, not individual tick samples; it is reported separately.
Exact full-engine physics p95 remains unavailable, not silently substituted by
callback p95. Fixed-size timing histograms avoid memory growth from recording
millions of samples. Client arena and baseline construction timings are separate
and exclude first import, network download and rendered shader/frame work.

The runner records CPU identity, source commit/dirty state and all eleven process
IDs/logs/reports. UDP rates count one network path (not both relay hops), including
28 IPv4/UDP bytes per datagram, in decimal KB/s. Process private bytes/working set
are sampled every five seconds; a full soak compares first/final measured-minute
medians. Short tests explicitly remain smoke evidence and cannot pass the soak.

## Local validation, 2026-09-19

Five-minute measured smoke after ten seconds warm-up passed on AMD Ryzen 9 9950X3D
(16 cores/32 logical processors), Godot 4.7.2, eleven headless processes. Report:
`%TEMP%/battlebots-performance-949a67da57324b6d888ad98b27ed0b6b/report.json`.
Measured 300.002 seconds at 59.996 Hz, one completed normal match and one rematch.
Authored contacts: vertical 55, horizontal 241, lifter 12, hammer 53, saw 65.
Session callback p95 upper bound was 1.30 ms (ten-live subset 1.39 ms); maximum
sampled engine physics window was 8.651 ms. These are not full-engine tick p95.
Per-player whole-run averages were 92.76–95.72 KB/s down and 6.52–7.18 KB/s up.
Ten-second downstream peaks reached 113.62–113.93 KB/s around lifecycle traffic,
so average success does not establish the full bandwidth budget. Burst reduction
remains open alongside the sixty-minute soak, deployment hardware and rendering.
The run used the dirty increment; peer scripts/gameplay were unchanged during
measurement. The final runner additionally records source SHA256 manifests and
surfaces each client's rolling peaks in the aggregate. Its parser, manifest
coverage and median calculation checks passed.

Baseline, combat physics/event kinds, snapshot recovery, detailed result bounds,
profile-zero 5v5 and contact 80/150 ms passed. Worst contact settling was 183.3 ms.
Saw CI 35467391486 passed all A MVP checks, then failed B's obsolete fourteen-row
catalogue expectation. The minimal fixture repair checks the actual registry and
each canonical part, including all five weapons; its targeted test passes.

Next priority per user: public matchmaking with externally hosted dedicated
game servers to remove tunnelling. Full soak is deferred while that increment
is prepared; neither a soak pass nor internet deployment is claimed here.
