# Measure applied prediction corrections (#57)

Windows MVP CI on main `1afa3b0` failed the 80 ms non-contact correction gate
with p95 **0.268749 m**. The pinned Linux engine reproduced the same value.
The value was one 60 Hz tick of ordinary travel at 16.125 m/s: snapshot receipt
compared the current node pose with replay's target for the next physics callback.
It was not the displacement actually applied to the body.

An independent listener on `DriveBody.reconciled` measured 27 corrections during
the 80 ms run, p95 **0.105019 m**, maximum **0.147026 m**, while the old diagnostic
still reported 0.268749 m. These figures describe that run, not universal bounds.

`MvpSession.diagnostics.correction_m` now records the latest displacement emitted
by the local body's existing `reconciled` signal, after collision-constrained
replay is applied in `_integrate_forces`. A newly established baseline resets
the diagnostic to zero and subscribes the new local body. Remote bodies do not
contribute. The latest value remains available between corrections.

The network regression samples each applied correction exactly once in its
measurement window, requires at least eight fresh samples, and independently
checks that the session diagnostic agrees with each emitted displacement.
The 80 ms p95 limit remains **0.25 m**. This avoids counting stale diagnostic
values repeatedly on physics ticks with no new correction.

Physics, replay targets, collision constraints, smoothing, commands and snapshots
are unchanged. This is a diagnostic/acceptance fix, so no gameplay build or
protocol change is needed. Platform CI and final release evidence are tracked on
[#57](https://github.com/fumbleforce/battlebots/issues/57). Network impairment in
this fixture affects the existing unreliable-message simulation, not all UDP
traffic, and the lifecycle checks use test eliminations rather than natural combat.

Validation: pinned Linux baseline and full drive/heavy/perk suite pass. Real
four-peer session checks pass at profiles 0, 80 and 150 ms, including diagnostic
consistency, fresh-sample count, reconnect, results and rematch. The measured
steady-driving p95 was 0 m in these runs; acceleration/transient corrections are
not asserted to be zero. Windows CI remains the platform acceptance gate.
