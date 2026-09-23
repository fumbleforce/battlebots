# Conventional reverse steering — 23 September 2026

Task [#43](https://github.com/fumbleforce/battlebots/issues/43), session
`reverse-steering-codex-x3d-20260923-1530`, branch `codex/b-reverse-steering`.

The same left/right input now produces opposite yaw when backing up. Forward
steering and neutral differential pivoting retain their existing directions.
Steering follows actual travel, so reverse coasting remains intuitive and pressing
reverse while still moving forward does not abruptly flip yaw during deceleration.

The shared `DriveModel.forces` projects velocity onto the chassis forward direction
in its support plane. Above 0.25 m/s it uses that signed speed to choose yaw
orientation. Near standstill it uses reverse throttle, or the normal orientation
for forward/neutral throttle. This suppresses resting-contact noise and allows
reverse steering immediately from rest. The threshold is the named
`motor.steering_direction_threshold` setting in `data/bot_physics.json`.

Practice pilots convert their desired facing yaw through the same steering-direction
helper, preserving aim while retreating. Live Jolt drive and client replay already
call this same function; neither input
adapters nor the camera/turret need inversion. Acceleration, traction, yaw rate,
braking, damage scaling and airborne gating are unchanged. Gameplay BUILD is
`mvp-ab-23`; protocol 10 and catalogue 13 are unchanged. Matching clients and hosted
workers must share the new build before online play is considered ready.

## Validation

The new `reverse_steering.gd` regression fails on the previous implementation
and passes with the new rule. It covers left/right in forward/reverse, reverse
coasting, both direction transitions, near-rest noise, stationary pivots, braking,
disabled steering, rotated chassis/sloped support, and decoded-command replay.
The MVP runner registers it.

Pinned Godot 4.7.2 `check-drive.ps1` passes baseline/import, actual Jolt drive,
heavy-drive physics and perks. The drive smoke now checks both left/right for
forward and reverse, in addition to existing coasting, brakes, neutral pivot,
input timeout, airborne, upside-down and wall-retreat checks. Heavy-drive replay
remains within its existing position/rotation acceptance bounds. Jolt emitted a
job-pool exhaustion warning during the accelerated heavy/perk tests; both passed.

The real Practice NPC lifecycle/combat test and the localhost network session
check pass (snapshot maximum 516 bytes; correction p95 0.25 m).

Hosted deployment and external duel evidence will be recorded on #43 after
integration; local tests alone do not establish the live server version.
