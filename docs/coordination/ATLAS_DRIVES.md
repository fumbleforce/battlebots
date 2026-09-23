# Atlas MX drive configurations (#47)

User request, 23 September 2026: give Atlas MX more upgrade/configuration
options — legs, large wheels — at the approved Atlas fidelity. Live status and
claims are on [#47](https://github.com/fumbleforce/battlebots/issues/47).

## What changed

Atlas now accepts three existing drive parts, each with its own authored
running gear. No catalogue part, loadout schema, command or snapshot changes.

| Drive part        | Running gear (`AtlasGeometry.DRIVE_GEAR`)                            | Physics            |
|-------------------|----------------------------------------------------------------------|--------------------|
| `traction`        | `tracks`: the approved V5 tracks in `atlas_mx.glb`, unchanged         | tracked probes     |
| `standard_wheels` | `wheels`: four 0.93 m lugged off-road tyres on finned hub motors     | wheel probes       |
| `walker`          | `legs`: four yaw/pitch/pitch hydraulic legs                          | `WalkerDrive`      |

`agile` remains invalid on Atlas (no modelled gear). Validation, the garage's
compatible-part filter and in-match drive pickups follow the same rule; an
Atlas *body* pickup still brings its tracks.

## Construction

Generator: [`tools/build-atlas-drives.py`](../../tools/build-atlas-drives.py)
(Blender 5.2). It imports the approved `atlas_mx.glb` and reuses its two sponson
surfaces exactly — hood, corner mount sockets, skirts, backbone plate and main
axle bosses — deleting only the track mechanism's connected components (road
roller stubs, swing arms, return-roller axle; 628 faces per side). The trimmed
sponsons keep the approved hull maps. The runtime hides the hull's
`DriveLeft`/`DriveRight` and shows `atlas_drives.glb` instead.

- **Wheels.** Tyre lug tips R .467, width .36, centre (±.945, −.085, ±.76): the
  bottom is at Y −.552 like the track shoes, so the shared ground depth .555 and
  the collision box are unchanged, and the tyres stay inside the former track
  envelope (X .753–1.137, clear of the skirt at 1.169 and the guard plate at .745).
  Lathed carcass, 20 pitches of staggered chevron lugs wrapping the shoulders,
  bead protectors, painted rim barrel, six forged spokes with real windows onto
  the hub motor, bolted machined beadlock, eight hex lug nuts and the approved
  domed hub cap. A static finned hub motor with caliper bolts to each axle boss.
- **Legs** (revised after user review: the first legs were far too spindly).
  Parts are modelled in authoring units and scaled ×1.5 about their joint
  origins, so every section, pin, planetary hip drive, knee ram and foot is
  heavier while the published lengths and pivots stay exact (femur .60,
  tibia .80, ankle .24 above the sole). A static slewing mount (web plate on the
  axle boss end face, two bearing collars) carries a coxa spindle at
  (±1.19, −.03, ±.86); the coxa fork holds the femur pin .235 out and the
  planetary hip drive on its outboard plate (left/right variants keep it
  outboard). Box-section femur with bolted top armour, knee fork and hose;
  tapered tibia with ram horn, bolted shin guard and ankle socket; ball ankle,
  rubber dust boot and a .31 m bolted pad foot with a cleated sole. A single
  knee ram (≥ .09 m gland overlap).
- **Walker footholds.** The heavier hips sit outboard of the axle bosses, so
  Atlas on legs stands on its own footholds just outside the hull corners,
  (±1.40, ±1.20) source metres (4.2 × 3.6 m game), instead of the chassis-derived
  default (±1.12, ±1.04). `AtlasDriveRig.foothold` is authoritative: MvpBot sets
  `DriveBody.walker_footholds` and `WalkerDrive.support` probes there; the legs
  are drawn on the same points. Wider stance = steadier on slopes (gameplay).
- Materials reuse the approved classes (primary/secondary enamel, machined,
  oxidised, recess, rubber) plus a tyre compound with dried-mud grime and
  hard-chromed ram rods, baked by `atlas_surface_bake.py` into a separate
  `Atlas_Drive*` set: Primary 2048, Secondary 2048, Hardware 4096, each with
  base/ORM/normal and enamel coverage maps (mipmapped like the hull maps).

## Runtime contract

- `data/atlas_drive_rig.json` (generated with the GLB; do not edit) is read by
  the typed [`AtlasDriveRig`](../../battlebots/scripts/core/atlas_drive_rig.gd)
  loader, which rejects missing fields. It carries the wheel radius and leg
  dimensions, footholds, coxa yaw stops (−10°/+60° from fore/aft) and the ankle rise limit.
- [`AtlasLegs`](../../battlebots/scripts/presentation/atlas_legs.gd) extends the
  shared `WalkerLegs` planted-foot gait. `AtlasLegs.solve()` is the same
  construction as `pose()` in the generator: heading from the slewing axis to the
  ankle (clamped to the yaw stops), femur/tibia two-link solve in that vertical
  plane with the knee up and outboard, foot aligned to the ground normal, knee
  ram aimed eye to eye. Feet use the rig footholds at `RIDE_HEIGHT`, the same
  points WalkerDrive supports the hull on; presentation never moves authority.
- The ankle folds at most `ankle_rise_limit` (.20 m) above stance: WalkerDrive
  lifts the hull onto a higher foothold, so taller rises are brief, and folding
  further would put the tibia into the slewing mount.
- `AtlasVisual.drive_gear`, `.drives` and `.legs` expose the fitted gear. Wheel
  pivots join the existing travel animation; drive meshes register left/right
  for component damage; repaint uses the drive coverage maps.

## Validation (Linux, RTX 3080, Godot 4.7.2, Blender 5.2.2)

- Generator clearance audit (manifest `clearance`): sampled triangle overlap
  against the imported hull and the trimmed sponsons. Wheels: 0 contacts over 8
  spin phases per wheel. Legs: 0 contacts over 63 foot offsets per leg (fore/aft
  ±.16 — the gait's maximum step lead — lateral ±.08, height −.45…+.41 m, the
  WalkerDrive reach and step range), including non-adjacent part pairs and the
  rotating coxa against its own mount (added after it exposed collar arms that
  reached through the spindle in the first version). Only the bolted hub motors and slewing
  mounts touch the axle bosses (reported as intended contacts). This is a
  sampled surface test, not continuous or volumetric proof.
- Design lesson: an under-femur lift ram needed a 2.1× eye-distance range over
  that envelope and fouled the folded tibia; a searched set of ram layouts found
  none with a realistic stroke. The femur therefore pitches on a rotary hip
  drive; only the knee keeps a ram.
- `tests/presentation/atlas_drives_test.tscn` (native): validation per drive,
  rig loader rejection, gear swap, wheel spin/drift, runtime solver reproducing
  every authored neutral leg transform in the GLB (to 0.5 mm), knee/ankle chain
  continuity, yaw stop and rise limit, soles planted on a physics floor, drive
  enamel repaint. A perturbed rig makes it fail as intended.
- `tests/presentation/atlas_drives_showcase.tscn` (native): Practice in the
  Foundry (wheels, legs, tracks) and Woodland (legs) under ordinary throttle and
  steering, plus both garage previews; checks travel, wheel roll and planted
  feet after walking. Captures go to `battlebots/exports/atlas-drives-review`.
- Existing checks rerun: baseline import + smoke, content, Atlas catalogue
  (updated to the new rule), pickups, drive, heavy drive/spawn, Atlas grounded
  modules, Atlas assembly and turret visual, component mesh mapping, visual
  load, all body weapons, garage preview/options/compatible parts/catalogue and
  Customize text, walker, geometry budget, pickup presentation.

## Cost

Per bot: sponsons 27.8k triangles; four wheels plus hub motors 113.5k (22.5k per
wheel); four legs 116.6k (29.2k per leg including its mount). In a scoped
Foundry Practice frame (camera 9 m from the bot, 1600×1000, 120 frames, native
RTX 3080) scene primitives averaged 1.683M with tracks, 1.727M with legs and
1.950M with wheels (shadow passes included); draw calls fell from 2459 (tracks)
to 2117 (legs) and 1493 (wheels). Frame time stayed at the 16.7 ms vsync cap in
all three. Not a low-end, four-bot or long-soak measurement. Godot generates LODs
on import.

## Not claimed / follow-up

- User visual approval of the new configurations is pending (#47).
- A 6×6 option for `agile` is not modelled; `agile` stays rejected on Atlas.
- Walker footfall audio uses no Atlas-specific samples yet.
- Hosted play needs the matching automated release of the build that carries
  this rule change.
