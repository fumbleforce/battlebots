# Nimble bots: Strider 09, Hellwheel 07, Pogo 03, Skater 12 (#61)

User request, 23 September 2026, with a four-bot concept sheet: make these bots
playable but not modifiable (yet), give each a unique gait/way of moving, let
them be NPCs, and make them quick and nimble, faster than the tanks. Live
status is on [#61](https://github.com/fumbleforce/battlebots/issues/61).

## What they are

| Preset | Chassis / drive | Weapon | Gait (`GaitDrive`) |
|---|---|---|---|
| STRIDER • 09 | `strider_09` / `stride_legs` | hammer arm | **stride**: a reverse-knee biped. Target speed surges once per step, the hull bobs (fed-forward so the spring follows the cadence) and sways over each planted foot; pivots quickly on the spot. |
| HELLWHEEL • 07 | `monowheel_07` / `mono_wheel` | minigun | **roll**: the fastest. Leans into turns (atan of lateral acceleration over g, capped at 30°), pitches with throttle, slides on a loose tyre and barely pivots at rest (30% turn rate until 7 m/s). |
| POGO • 03 | `pogo_03` / `pogo_spring` | minigun | **hop**: moves in spring-loaded bounds. After a stance on the spring it launches at the jump-scaled hop speed carrying the driven heading speed; steers and trims speed in the air, lands on the spring. |
| SKATER • 12 | `skater_12` / `skate_legs` | twin minigun | **skate**: alternating push strokes and glides with very low coast drag (glides ~7× further than a tank after release), carves with a modest lean and crouches at speed. |

Measured on real Jolt (flat floor, `tests/simulation/nimble_gaits.gd`): top
speed tank 12.5 m/s, standard wheels 16.1; Strider ≈21, Hellwheel ≈25,
Pogo ≈21.5, Skater ≈23 m/s.

All four are light (≈60 kg), accelerate hard and carry **no armour pieces**:
every hit reaches the core, so speed is their defence.

## Sealed factory builds

- `data/mvp_parts.json` revision 17 adds the four chassis and their four
  drives. `ContentRegistry.validate` (via `NimbleBots.reasons`) requires each
  nimble chassis to keep its drive, weapon and utility and a paint-only
  cosmetic record; perks (Nitro, charged jump) remain free. A nimble drive on
  any other body is rejected.
- Menus: the four presets are built-in (`PlayerProfile.PRESET_COUNT` 18).
  They can be selected in the garage, lobby and practice, and driven. The
  garage disables CUSTOMIZE and the loadout links for them;
  `PlayerProfile.sealed()` also makes equip, repaint, rename and save no-ops.
  Customize never lists the nimble chassis or drives. Match pickups never
  drop the drives, and a nimble bot takes perk pickups only.
- To allow customisation later, relax `NimbleBots.reasons`/`sealed()` and add
  modules the models can mount.

## Physics

`GaitDrive` (simulation) replaces the ground probes for bots whose
`DriveBody.gait` is set. Like `WalkerDrive`, down rays under the bot's
footholds find the floor and a damped spring holds the hull centre at
`ride_height`. Legs, wheel and spring are not supports, but they are solid:
the Strider and Pogo add a `leg_collision` box with the hull's footprint under
the hull (ending ≥0.45 m above the floor) and the monowheel adds its tyre
cylinder. A narrower column let the hull's lower edge ride up over the 3 m
Foundry wall; with the full footprint a wall meets a flat face. Support only
lands within `max_step` of the last floor stood on, and a launched pogo has no
spring support (or rebound lift) until it falls, so a bound peaks ~1.8 m up
and cannot carry it onto a wall. A bounded torque keeps the hull aligned with
the floor plus the gait's lean. Each gait then shapes the shared
`DriveModel` config (speed surge, turn authority, push/glide drive) before the
ordinary tyre forces. Hop launches and air control happen in `DriveBody`
around the grounded check. Gait phase, stance timer, lean and crouch are local
body state and reset with `reset_pose`.

All tuning is in `data/nimble_bots.json` (typed, validated by `NimbleBots`;
missing fields are errors, never defaults). Weapons reuse the existing rules:
the Strider's hammer sweeps from `hammer_socket`, the gun bots use the shared
Scorpion gun frame moved to `gun_pivot` (`AtlasGeometry.gun_offset` returns the
nimble offset), so authoritative shots and effects start at the modelled muzzles.

**Prediction limit.** `DriveModel.replay` (client correction extrapolation)
does not model gait shaping; online, a predicted pogo bound or stride surge is
corrected by the next snapshot. On local ENet (`tests/network/nimble_session.gd`)
the largest applied correction was 0.47 m for a bounding Pogo and 0.37 m for
the Skater; both settle onto the authoritative pose. Before the wall fix a
Pogo that cleared the wall was teleported back by the out-of-bounds reset
(a 12.8 m correction). Offline practice runs the authority locally.

## Practice NPCs

`PracticeBotDirector.roamers` adds the four bots in Foundry and Woodland
(`practice.arenas`), on a diagonal ring at 55% of the arena half extent,
facing the centre. They race six-point patrol loops around their homes and
engage a player within 20 m with the ordinary pilot, respawn like other NPCs
and reset with practice restart. They are kept apart from the authored
`records`, whose indices the Woodland edge starts (#45) use. Moon (50 m) has
no roamers.

## Models and presentation

Generator: [`tools/build-nimble-bots.py`](../../tools/build-nimble-bots.py)
(Blender 5.2; `-- --no-render` skips review renders) builds all four from the
shared `atlas_model_kit` helpers and reads ride heights, footholds, gun pivots
and the hammer socket from the data files, so model and simulation agree.
Outputs: `assets/models/nimble_runtime/*.glb` and `nimble_manifest.json`.
Every moving assembly is a named empty: limbs hang along −Y from their pivot,
wheels spin about X, the pogo coil stretches along −Y, the gun follows the
shared GunFrame → GunMount → GunBarrels/Muzzle contract.

`NimbleVisual` only observes accepted `BotView` poses: stride feet cycle with
travel at the physics step length and plant on raycast ground with backward
(digitigrade) knees; the monowheel tyre rolls without slip; the pogo hub
squashes to the floor and sags in the air while the coil stretches; the skater's
rear wheels kick back and out while it accelerates, and its wheels roll. The
hammer arm follows the shared hammer states. Camouflage and hazard enamels are
triplanar pattern materials at runtime.

**Art status: first pass.** Flat PBR material classes, no baked maps, wear,
AO or coverage textures (see [the asset guide](../art/STYLIZED_INDUSTRIAL_ASSETS.md));
no clearance audit over the gait envelope. Triangles: Strider 16.9k,
Hellwheel 15.0k, Pogo 10.3k, Skater 39.0k. User visual approval is pending.

## Validation

- `tests/simulation/nimble_gaits.gd` (headless, real Jolt): validation locks,
  top speeds above the tank, stance heights, one measurable signature per gait
  (stride bob/surge, monowheel lean and weak pivot, pogo air time and bounds,
  skater glide) and a 3 m wall that no gait crosses at full speed.
- `tests/network/nimble_session.gd`: server refuses a modified factory build,
  accepts the presets, authority and prediction run the gait, corrections stay
  under 2 m and bodies settle on the authority.
- `tests/presentation/nimble_garage_test.gd`: sealed presets in the garage and
  profile, Customize/pickup exclusions, revision-16 migration.
- `tests/practice/practice_npcs_test.gd`: roamers spawn, run their gaits and
  patrol on normal commands; authored NPC fixtures unchanged.
- `tests/presentation/nimble_showcase.tscn` (native): each preset in Foundry
  practice idle, running, turning and attacking, plus a roamer overview.
  Captures go to `exports/nimble-review` (`NIMBLE_CAPTURE_DIR` overrides).
