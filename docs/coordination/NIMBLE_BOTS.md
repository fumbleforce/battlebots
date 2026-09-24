# Nimble bots: Strider 09, Hellwheel 07, Pogo 03, Skater 12 (#61)

User request, 23 September 2026, with a four-bot concept sheet: make these bots
playable but not modifiable (yet), give each a unique gait/way of moving, let
them be NPCs, and make them quick and nimble, faster than the tanks. Live
status is on [#61](https://github.com/fumbleforce/battlebots/issues/61).

## What they are

| Preset | Chassis / drive | Weapon | Gait (`GaitDrive`) |
|---|---|---|---|
| STRIDER • 09 | `strider_09` / `stride_legs` | hammer arm | **stride**: a reverse-knee biped. Target speed surges once per step, the hull bobs (fed-forward so the spring follows the cadence) and sways over each planted foot; pivots quickly on the spot. |
| HELLWHEEL • 07 | `monowheel_07` / `mono_wheel` | minigun | **roll**: the fastest. Rides on its tyre (ride height follows the tyre's contact as it leans), leans into turns (atan of lateral acceleration over g, capped at 30°), pitches with throttle, grips at its contact patch and never turns tighter than 75% of its grip holds (#75), and barely pivots at rest (30% turn rate until 7 m/s). Heavier than the others (44 kg chassis) and 3× weight on the Moon (`low_gravity_heft`). |
| POGO • 03 | `pogo_03` / `pogo_spring` | minigun | **hop**: moves in spring-loaded bounds. Its pads grip the floor during the stance (planar speed and yaw decay, no motor), then it launches at the jump-scaled hop speed carrying the driven heading speed; steers and trims speed in the air, lands on the spring. |
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
the floor plus the gait's lean; it never includes a vertical (yaw) component,
because on a leaned hull the tilted correction axis spun a braking monowheel
up to 10 rad/s (user report, 23 September). Each gait then shapes the shared
`DriveModel` config (speed surge, turn authority, push/glide drive) before the
ordinary tyre forces.

**Contact with the floor (#75, user report 24 September: the monowheel hovered
a lot and the pogo slid).** Every bot's `reach` is how far below the hull its
gear can touch the floor (Strider 4.6, Hellwheel 2.25, Pogo 4.2, Skater 3.1),
so the spring never carries a hull whose gear dangles above the floor; the
Hellwheel used to float down from 1.5 m above its tyre contact after a jump.
The monowheel's ride height is its tyre contact depth: `GaitDrive.tyre_depth`
revolves the measured tyre profile (`wheel.profile`, flat crown and rounded
shoulders) about the leaning, pitching axle, plus 0.03 m `clearance`; the
tyre collider is the same revolved profile (`NimbleBots.tyre_points`, a convex
hull) instead of a sharp cylinder. Its tyre forces act on the contact patch
velocity (`GaitDrive.grip_velocity`), so leaning moves the hull over a still
patch, and its turn rate is capped at `carve_grip_share` of grip over speed,
so it carves rather than skids (`lateral_response` 0.15, was 0.45). The pogo
grips during its stance (`GaitDrive.stance`: planar velocity and yaw decay at
`hop.stance_grip` 30/s; no motor) and launches with the full driven speed
(`carry` 1.0). Hop launches and air control happen in `DriveBody`
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

Generators (Blender 5.2, one process per bot; `-- --quick` for 1024/512
review bakes, `--no-bake`, `--no-render`): `tools/build-nimble-strider.py`,
`build-nimble-monowheel.py`, `build-nimble-pogo.py`, `build-nimble-skater.py`,
on the shared [`tools/nimble_model_kit.py`](../../tools/nimble_model_kit.py).
They follow [the asset guide](../art/STYLIZED_INDUSTRIAL_ASSETS.md) (user
feedback, 23 September: the first pass was too basic and must not copy Atlas
colours — Atlas is the fidelity reference): a written construction brief in
each docstring; armour fitted over a backing structure with narrow seams;
folded sections; real recessed vents and bores; pocketed lenses; lathed hubs,
tyres, spring and collars; seated fasteners; per-bot palettes taken from the
concept sheet. Each run audits clearance of its moving assemblies over sampled
gait/weapon poses (all clear; sampled, not continuous), bakes portable PBR maps
through `tools/atlas_surface_bake.py` (enamel/primer/chip wear, local AO, ORM,
normals, coverage; the moving assemblies are isolated during the occlusion
bake) and exports GLBs that reference `Nimble0x*`/`Nimble12*` maps. The baker
gained additive `atlas_camo` / `atlas_stripes` material properties and a
`primary_color` argument; Atlas output is unchanged. Triangles: Strider 55.5k,
Hellwheel 59.7k, Pogo 59.8k, Skater 69.9k.

Every moving assembly is a named empty: limbs hang along −Y from their pivot,
wheels spin about X, the pogo coil stretches along −Y, the gun follows the
shared GunFrame → GunMount → GunBarrels/Muzzle contract.

`NimbleVisual` only observes the drawn (interpolated) hull pose and `BotView`;
it plants the running gear without sliding (#75):

- **Strider:** feet stand where they land (world points). On the GaitDrive
  cadence each swings to the spot under the hull at the middle of its next
  stance (predicted from velocity and yaw rate), lifting and setting down
  vertically with a slight toe dip; a stretched standing leg hurries the
  stride; stopping finishes the step and both feet stand; at rest a foot only
  steps again when 0.45 m out of place; out of reach of the floor the legs hang.
- **Hellwheel:** the tyre spins by its contact patch's own forward speed over
  the patch's distance from the axle (the patch moves onto the rounded
  shoulder and off the centre line when leaning).
- **Pogo:** when the pads reach the floor they plant (world point and heading);
  the level tripod stays there, the hub squashes and the head leans over the
  planted tripod (up to 20°) as the hull moves, including through the push-off
  until the spring is fully extended; in the air the hub sags and the head
  levels.
- **Skater:** each fork swivels about its shin (new `Fork*` nodes, regenerated
  model) so the tyre points along its own travel, castor-like, and the wheel
  rolls by that travel over its contact radius; the wheel is set so its
  lowest tread point (measured profile) touches the floor probed along the
  hull's down axis. Push-stroke kicks ease in and out.
- **Charged jump:** the legged bots crouch with `jump_charge_fraction`
  (planted gear bends) and spring back on release.
- **Hammer (Strider):** carried low beside the hull (no longer across the
  visor) with a walking swing; the 0.35 s wind-up dips then cocks past
  vertical with the body leaning back; at the authoritative strike it slams
  to −30° in 0.06 s with a forward lunge, rebounds and recovers over the 1.4 s
  cooldown.

`tests/presentation/nimble_contact_test.tscn` (headless) measures it: the
lowest vertex of every foot, tyre and pad against the floor each frame over a
scripted course (idle, run, carve, pivot, stop, reverse, jump charge, landing),
and the slip of the touching material point (the rim bottom for tyres).
Before → after (mean gap / hovering frames / mean slip / 95th percentile slip):
Strider 0.006 m / 3% / 4.0 / 20 m/s → 0.000 / 0% / 0.04 / 0.00; Hellwheel
0.22 m / 97% (tyre never touched) → 0.03 / 1% / 0.5 / 1.1; Pogo 0.06 / 22% /
9.3 / 21 → 0.002 / 1% / 0.35 / 0.01; Skater 0.02 / 3% / 1.7 / 5.7 →
0.000 / 0% / ~0.6 / 1.5.

Not yet: the Strider hammer has no separate telescopic ram node (the ram does
not retract), and a native visual review of the new animation is pending
(user review). Known gaps (builders' own notes): the Strider's legs are slimmer and its head
cleaner than the concept, and its hammer rests across the face; the Hellwheel's
hub/neck is less dense than the concept; the Pogo keeps the shared rotary gun
rather than the concept's single cannon; the Skater reads flatter than the
concept because of its collision box and long shared barrels; chip wear is
tuned for Atlas's size (face_wear raised to 0.80–0.82). Boolean cuts leave a
`material_index` attribute that darkens the baked AO unless removed (the Pogo
generator does). User visual approval is pending.

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
