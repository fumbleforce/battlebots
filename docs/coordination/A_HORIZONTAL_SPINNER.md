# Horizontal spinner — Developer A

Branch codex/a-horizontal-spinner, based on db87257. The updated menu/music
playtest export is ready and preserved. Resume the remaining spec work here.

Owned changes: canonical part entry, authoritative resource/charge state,
swept side-contact damage/recoil, simple bot visual, compatible local save
migration, build marker and independent state/physics/network tests.
Subagents separately own state/catalogue, physics regression and ENet regression.

Spec gates: 30 kg/40 power; two-second spin-up; 25% charge damage threshold;
40 raw damage scaled by charge; consume 60% charge per hit; one hit per target
per 0.3 seconds; 10 battery and 12 heat per powered second. Friendly, disabled,
overheated and eliminated attacks cannot produce weapon hits. All hits remain
server-owned and use existing event IDs/server ticks and replicated state.

Authored geometry: front-mounted horizontal disc, radius 0.65 × chassis width,
height 0.24 m, center at chassis local (0, 0, -length/2 - 0.2). Sample body pose
along translation and rotation before applying that offset, so turning sweeps
an arc instead of a chord. Contact produces 4 m/s horizontal target impulse
and 60% opposite momentum recoil to the attacker, with no authored vertical
launch. These are provisional impulse/envelope values for playtesting, separate
from fixed damage/charge specification. Existing vertical/lifter behavior stays.

Validation: pure state/catalogue checks pass; independent Jolt scene passes
full-charge/threshold plate and component damage, cooldown, friendly/disabled/
overheated/wreck exclusions, side geometry, translation and half-turn arc sweeps.
The impulse fixture measures 4 m/s horizontal target motion with 60% opposite
momentum recoil and zero authored vertical velocity. Simple visual mount/radius/
rotation/disabled checks pass without adding colliders.

Real ENet checks cover canonical host/client loadouts, actual held input,
authoritative hits/effects/state, physical recoil snapshots, reconnect and round
reset. At 80 ms injected input/snapshot RTT with jitter/loss, local presentation
stayed inside 0.25 m/10 degrees (0.203 m peak) for two seconds after the hit.
The 150 ms profile also passes with a 0.228 m peak and zero angular error,
remaining in tolerance over the same two-second window. Both reconnect/reset.
Reliable control is not impaired by this fixture; prior whole-UDP suites remain
separate. All new checks are registered in the MVP runner, networking per profile.

Baseline/drive, existing combat physics/rules, content/save migration and menu
profile checks pass. Existing 80 ms contact regression also passes (lifter
183.3 ms, vertical spinner 150 ms; impulse/ram/recovery within their gates).
Known revision-one local saves migrate by validating current stats without
changing selected parts; unknown hashes/parts remain invalid. Hashing normalizes
line endings for Windows/Linux parity. Build is mvp-ab-6, protocol remains 4.

Human contact feel and full multiplayer performance/soak remain separate
acceptance work. The menu/music ZIP from db87257 remains unchanged.
