# A hammer increment

Owner: Developer A. Branch: `codex/a-hammer`, based on published horizontal
spinner `b46084e`. The menu/music playtest ZIP at `db87257` stays available.

Reserved: combat state/world, canonical catalogue/registry/save migration,
primitive bot weapon assembly, independent simulation/network fixtures and A checks.
Small integration changes expose the Duelist starter in PlayerProfile and preserve
physical press edges in B's hold/toggle input adapter. No modelling assets change.

Target: 24 kg / 35 power hammer, 38 raw damage, committed overhead sweep after
0.35 seconds, 1.4-second recovery even on a miss, 16 battery / 20 heat per strike.
Each physical press can begin one attack; holding never repeats it. Release and
secondary do not undo a committed strike; inactive/eliminated/destroyed state cancels.
Charge reports windup progress; phase reports windup/strike/cooldown. Existing
snapshot fields suffice. Duelist is compact/agile/hammer/standard armor/cooling.

Validation: independent state timing/resources, real Jolt curved sweep/zone/hit
deduplication, real ENet press and observer state, plus affected regression checks.
Implemented: revision-three catalogue and `registry.duelist()`; build mvp-ab-7,
protocol 4. Local revision-one/two saves migrate only after validating unchanged
parts and cosmetics. Network build/content checks remain strict.

Acceptance spends 16 battery and increments attack ID. After 21 ticks at 60 Hz,
the swing emits one strike pulse, adds 20 heat and starts 1.4-second recovery.
A strike reaching heat 100 completes; further starts lock until heat 50. Destroyed
or inactive state cancels windup. Self-righting and the one-second recharge delay
remain available; held input and presses during recovery cannot queue attacks.

Provisional geometry: pivot at local (0, height/2, -length/2 + 0.15), 1.2-m arm,
0.2-m spherical query head. Head descends from 90 to -30 degrees about local X;
queries follow both its curved path and chassis translation/rotation, sampled
at most 0.08 m apart. First contact routes through the actual victim damage zone.
Authored impact adds 1 m/s downward along attacker-local up with 20% opposite
momentum recoil. These reach/impulse values remain playtest tuning parameters.

Independent Jolt fixture passes overhead 38 raw / 36.1 top-core damage, unchanged
side plates, two-target activation dedup, inactive/friendly/destroyed exclusions,
windup and recovery, narrow-reach misses, translation and turning sweeps.
State, primitive visual, catalogue migration, menu profile, hold/toggle input,
baseline, existing weapon state/physics and match-rules checks pass. Actual ENet
0/80/150-ms input/snapshot impairment cases pass two genuine presses/two hits,
holding through cooldown without repeats, observer windup/recovery and exact
health, reconnect and round reset. Reliable control is not impaired by this fixture.
After each actual hit, the local rendered pose is compared with authority for
2–2.5 seconds. All three profiles remain within 0.25 m / 10 degrees throughout;
the largest measured error is 0.003 m, with zero angular error. Thus settling
is reported as 0 ms against the 250-ms gate. This small grounded recoil case
does not replace the larger spinner/flip contact or human-feel acceptance.

Preceding CI: menu/music run 35465682771 passed. Horizontal run 35466215676 failed
the existing FFA exact-health observer gate after its horizontal checks had passed.
A bounded local FFA profile-zero reproduction passed, so no speculative production
change is included. The failing gate now prints captured/live server health and
each observer's core/tick/phase on failure; the assertion and timeout are unchanged.
Its underlying cause remains open for the next CI run.
