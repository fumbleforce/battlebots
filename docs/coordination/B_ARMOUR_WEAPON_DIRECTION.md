# Armour and weapon direction

Owner: B. Design issue: [#19](https://github.com/fumbleforce/battlebots/issues/19).
Prototype integration: [#39](https://github.com/fumbleforce/battlebots/issues/39).

The user's sketch (22 September 2026) asks for a protected core, per-side
plates, damage roles and distinct locomotion. The user accepted these decisions
on 23 September 2026:

- Plates are chosen **per face**. Presets set every face at once.
- Every bot has **two weapon sockets**. Any two weapons fit, limited only by the
  mass and power budgets.
- Rules go into a standalone module first. The game integrates them in #39, after
  the active catalogue and combat tasks (#36, #35, #38) release their files.

The rules live in `battlebots/scripts/simulation/armour_layout.gd`
(`ArmourLayout`). Its test is `tests/simulation/armour_layout_test.gd`, registered
in `tools/check-mvp.ps1`. **The live game still uses the legacy four-side package.**
All numbers are tunable seeds, not settled balance.

## Plate geometry

The core sits inside six plate faces: `front`, `rear`, `left`, `right`, `top` and
`underside`. The faces match the zones that `MvpBot.zone_at()` already resolves.
The top plate covers the top band, and the underside plate the bottom band. The
drive (`drive_left`, `drive_right`) and `weapon` zones stay exposed components.

Each face takes `none`, `light`, `standard` or `heavy`. The default layout is
standard on five faces with no underside plate. Top and underside plates cost the
same as side plates, because plate mass is a gameplay stat, not surface area.

| Class | Mass per plate | Reduction | Integrity |
|---|---:|---:|---:|
| none | 0 kg | chassis baseline 5% | 0 |
| light | 2.5 kg | 10% | 60 |
| standard | 4.5 kg | 25% | 90 |
| heavy | 6.25 kg | 40% | 120 |

Per-plate values are the legacy package divided by four. As a result:

- **Migration is exact.** `from_legacy_package()` fits the old class on the four
  sides and leaves top and underside bare. That matches today's mass (10/18/25 kg)
  and today's protection. The test checks this parity against the live `CombatState`.
- **The budget needs no change.** The mass ceiling stays at 120 kg and installed
  power at 100. A full armour set now costs 12.5 kg (five light plates) up to
  37.5 kg (six heavy plates). That price is the armour-for-speed tradeoff.

## Damage routing

`ArmourLayout.route(layout, zones, zone, raw, profile)` returns the zone and core
damage for one hit. It uses the zone state at the start of the hit.

- **Intact plate:** the plate takes `min(integrity, raw × plate)`. The core takes
  `raw × core × (1 − reduction × (1 − pierce))`.
- **Absent or destroyed plate:** the core takes `raw × core × 0.95`, the chassis
  baseline.
  - This is a deliberate change. Today a destroyed side plate lets 100% of raw
    damage through, while top and underside keep the 5% baseline. Every exposed
    face now behaves the same.
- **Drive and weapon components:** the component takes `min(integrity, 0.75 × raw × drive)`.
  The `drive` multiplier applies only to drive zones. The core takes
  `0.25 × raw × core`.

With the standard profile and intact plates, the result equals the current rules.

### Weapon damage profiles

| Profile | Plate | Core | Pierce | Drive | Sketch role |
|---|---:|---:|---:|---:|---|
| standard | 1.0 | 1.0 | 0 | 1.0 | Spinners, hammer, ramp, ram, minigun (unchanged) |
| piercing | 0.4 | 1.0 | 0.6 | 1.0 | Forward spike, armour-piercing cannon: low plate damage, high core damage |
| explosive | 1.6 | 0.5 | 0 | 1.0 | High-explosive cannon: strips plates, low core damage |
| cutting | 1.2 | 0.8 | 0 | 1.0 | Vertical saw: strong, concentrated |
| sweeping | 1.0 | 0.7 | 0 | 1.5 | Horizontal spinner: weaker, wide, and the pick against walker legs |

Current weapon mapping: the saw uses `cutting` and the horizontal spinner uses
`sweeping`. Every other weapon keeps `standard`.

The piercing and explosive profiles are ready for future weapons. #36's
turret cannon can take one of them once #39 lands. A hit's area of effect comes
from the hit geometry: the sweep shapes decide which zones a hit reaches, not the
profile.

## Mass effects

| Function | Rule | Purpose |
|---|---|---|
| `top_speed_factor(mass)` | `1 + (100 − mass) × 0.005`, clamped to 0.9–1.1 | Light builds are fast, heavy builds slow |
| `impulse_response(mass)` | `100 / mass`, clamped to 0.7–1.5 | Multiplier for fixed-impulse sources (gun recoil, blast shockwaves): light builds are thrown further |
| `ram_damage(closing, attacker, victim, drive)` | `2 × (closing − 4) × clamp(attacker/victim, 0.5–2) × drive factor`, capped at 24 | Collision damage follows momentum and drive |

The legacy 4 m/s ram threshold and 0.5-second pair cooldown are unchanged.

- **Top speed is a change to GAME_SPEC.** The spec currently says top speed comes
  from the drive alone. The sketch explicitly wants armour weight to affect speed.
  Drive-package top speed stays the base value; the factor adjusts it by at most
  ±10%.
- **Existing mass effects stay.** Mass already affects acceleration (`8 × 103 / mass`),
  the grip limit and the attacker/victim impulse ratio in `CombatWorld._apply_hit`.
  #38 is currently tuning impulse and motor strength. #39 applies
  `impulse_response()` on top of #38's result, not in place of it.

## Two weapon sockets

- A build has one or two weapons, limited by mass (120 kg) and power (100).
  `ArmourLayout.budget()` validates the proposed loadout shape.
- **The sketch's combination fits only by trading armour.** Ramp + hammer on
  Balanced with standard wheels uses exactly 100 power.
  - With five standard plates it weighs 125.5 kg, which is illegal.
  - With five light plates it weighs 115.5 kg, which is legal.
- **Two spinners exceed the power budget.**
- **Input:** the primary weapon uses LMB. The secondary uses RMB, which is the
  existing `secondary_held` and auxiliary trigger path. Both weapons share battery
  and heat.
- **Mounts:** each body needs an authored second mount. Two weapons may not share
  one swept volume. For example, a front ramp plus a top-mounted hammer that swings
  over the ramp is fine. #39 authors the Sawblade mount for ramp + hammer first;
  other pairs follow as mounts are modelled.
- **Minigun pod:** the `minigun_pod` utility migrates into the second weapon socket.

## Locomotion

Wheels and tracks currently share one probe model and differ only in catalogue
speed, grip and mass. Collision behaviour now also separates the drives:

| Drive | Ram factor | Direction |
|---|---:|---|
| Agile wheels | 0.6 | Fast and manoeuvrable; weak collision damage |
| Standard wheels | 0.8 | Balanced |
| Tracks (traction) | 1.5 | Heavy and stable; the unstoppable force |
| Walker legs | 0.5 | Climbs terrain; weak at ramming and melee reach |

Two proposals are left out of #39 and each needs its own task:

- **Walker crouch (sketch: Ctrl).** It lowers the hull so melee weapons reach, and
  doubles as a crushing attack. It needs a new `BotCommand` flag bit, a wire
  protocol bump and a rebindable input action. Those belong to B controls, with an
  A handoff for the protocol.
- **Track stability.** Tracks resisting impulses more than wheels belongs with the
  #38 physics tuning.

## Integration order (#39)

1. Loadout schema 3: a plate layout in place of `parts.armor`, a second weapon
   slot, and migration from schema 2.
2. `CombatState` creates six plate zones and calls `route()`.
3. `CombatWorld` uses the new ram damage and impulse response.
4. Snapshot `ZONES` gains `top` and `underside`. This bumps `SNAPSHOT_FIELDS`,
   `PROTOCOL` and `BUILD`, and changes the catalogue hash. A must make a matching
   hosted release.
5. Garage per-plate and preset choices, and a second weapon picker.
6. Prototype ramp + hammer against the 1v1 acceptance checks.

## Validation (Godot 4.7.2)

- `armour_layout_test.gd`: headless PASS. It covers layouts and presets, exact
  legacy parity with `CombatState` for all three packages, exposed and destroyed
  faces, clamping and invalid input, profile ordering, mass effects, and the
  two-weapon budget scenarios.
- `tools/check-baseline.ps1`: see the #19 progress comment for the result.
- No catalogue, schema, protocol or hosted-service change. No server release is
  needed for this increment.
