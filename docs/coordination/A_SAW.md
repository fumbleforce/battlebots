# A saw increment

Owner: Developer A. Branch: `codex/a-saw`, based on hammer `9610946`.
Reserved paths: A combat state/world, catalogue/save migration, primitive weapon
assembly, independent simulation/network fixtures and A check scripts. B's art,
menus/input and the modelling checkout are not part of this increment.

Implement `saw` (20 kg / 30 power): hold primary to power, 9 battery / 14 heat
per second. Maintained contact deals 6 raw every 1/3 second (18 raw per second).
Contact time starts at zero for each target and resets on separation, release,
secondary, disable, overheat or inactive match state. Short passes cannot bank
damage toward a later touch. No extra spinup, launch impulse or pin mechanic.
Existing active/idle/disabled/overheated phase and charge fields serve observers.

Provisional reach: vertical disc radius 0.32 m and width 0.16 m, mounted at
(0, 0.1, -chassis length/2 - 0.4), clearing the floor on an upright chassis.
Queries follow translation and rotation between
ticks; one contacted zone per cadence event. Primitive assembly matches the mount.

Acceptance: independent state/resources, Jolt cadence/zone/contact-break/sweep
scene, actual ENet held input and observer damage/reconnect/reset at 0/80/150 ms.
Catalogue revision four/build mvp-ab-8 keep protocol 4; both peers must update.
The menu/music playtest ZIP remains at db87257.

Implemented: per-target contact time, exact third-second pulses, unique attack
IDs and server ticks, first-overlap zone routing, and translation/rotation blade
sweeps. Inactive world tick gaps and round changes clear partial contact too.
No input adapter or snapshot format changes. Revision-three Duelist saves retain
their selected parts through validated local migration.

Independent Jolt checks pass: first hit on contact tick 20, three pulses/18 raw
in 60 ticks, exact rear plate/core, exposed drive and top damage, independent
target timers, six brief contacts producing no accumulated damage, all power/
contact interruptions, skipped inactive ticks/round changes, narrow misses,
friendly/wreck exclusion, fast translation/yaw sweep and zero authored impulse.
State/resource, simple visual, save migration, existing weapon state/combat/rules,
menu profile/input toggle and baseline checks also pass.

Actual ENet profiles 0/80/150 ms pass: three maintained cuts exactly 20 server
ticks apart, release stop, a fresh full cadence after restart, secondary stop,
unique effect/attack IDs, exact observer health/armor, token reconnect and round
reset. Four rear hits remove 24 plate integrity and 18 core (242 core/66 rear
remaining). Stationary contact adds no knockback. The simulator affects input
and snapshots, not reliable control; no whole-UDP claim is made for this fixture.
During active cutting, the local rendered pose is also checked against authority
at the existing 0.25 m / 10-degree tolerance. All three profiles pass across
87–96 active physics samples, with peak error rounding to 0.000 m / 0 degrees.

Hammer CI 35466883297 failed the existing five-v-five rematch spawn comparison
for two observer/entity pairs (<0.15 m gate); its hammer and horizontal profile-zero
checks passed, and FFA was not reached. A bounded local reproduction passed.
Failure-only diagnostics now include poses, snapshot/server ticks, snapshot age,
correction/freeze/clock state and ENet throttle. No speculative production fix or
weakened assertion is included. This and the preceding FFA convergence failure
remain explicitly tracked acceptance work.
