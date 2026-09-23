# Atlas MX turret — B, 23 September 2026

Issue: [#36](https://github.com/fumbleforce/battlebots/issues/36). Owner: B.
The user asked for a modelled Atlas turret carrying a cannon or plasma gun,
aimed by mouse and controlled like a tank game.

## Asset

`tools/build-atlas-turret.py` (Blender 5.2.1) generates `atlas_turret.glb`
and baked `Atlas_Turret*` maps in `assets/models/atlas_runtime/`. The
generator's docstring holds the construction brief. The user reviewed and
approved these revisions: 1.45× size, a boxy casting after the user's
references, a hollow cannon bore with an open brake, a longer and thicker
barrel with sleeves, clamp bands and low bolts, and baked barrel wear via new
optional per-material bake properties. Hull bake output is unchanged.

Nodes: `TurretYaw` (pivot `(0,.52,-.14)`), `TurretPitch` (trunnion
`(0,.77345,-.546)`), `AttachmentCannon`/`CannonRecoil`/`MuzzleCannon` and
`AttachmentPlasma`/`MuzzlePlasma`. Units are Atlas source metres; runtime
scale is ×3. `atlas_turret_manifest.json` records the clearance audit.
The audit samples triangle overlap against the imported hull GLB and finds the
lowest clear elevation per 5° bearing. It then verifies the runtime rule every
2.5°: −20° over the nose, −6…−11° on the flanks, about −18° at the rear.
With a turret fitted, the ArmorTop and exhaust modules are hidden because the
barrel sweeps them (cosmetic only).

## Gameplay and contracts

- Catalogue revision 11 (hash `9c24100bd8b1aa480137e9ab061d9190c6c75b4462b9456d2e32935c9f116751`) adds utilities `turret_cannon`
  (16 kg/25 power) and `turret_plasma` (14/25). They are Atlas-only and
  exclude the primary minigun. Revision-10 saves migrate. Preset
  `ContentRegistry.atlas_turret()` is seeded as the sixth profile preset.
- `BotCommand`: `aim_valid` (flag bit 9), `aim_yaw`, `aim_pitch`
  (world bearing and elevation from the trunnion). The wire command array
  has 6 fields. Snapshots append `turret_yaw` (40 fields). Elevation reuses
  `gun_pitch`; shots reuse `shot_sequence`/`last_shot_*`. **PROTOCOL 8,
  BUILD mvp-ab-18.**
- Server (`CombatWorld`): the servo slews toward the aim at 1.9/1.2 rad/s
  within the audited elevation profile, elevates before traversing, and is
  stabilised against hull motion. Rays run from the trunnion along the actual
  barrel. Walls and allies occlude. Cannon: 32 raw, 2.4 s reload, 14
  battery/16 heat. Plasma: 11 raw per bolt every 0.22 s, 3 battery/4.5 heat.
  Event kinds are `cannon`/`plasma`.
- Controls (B): turret builds view through `TankSightCamera`, which uses the
  rig's mouse state from a sight point above the turret. LMB fires the main
  gun, RMB operates the hull weapon. `TurretReticle` shows the crosshair,
  the actual barrel point and reload.
- Presentation: `TurretShotEffects` (recoil, flash, travelling
  projectile, lit billow smoke plus fog volumes, first-pass procedural
  reports in the `bot_action_audio` group).

## Validation

Godot 4.7.2 on Linux, RTX 3080. PASS: `atlas_turret_physics.tscn`,
`atlas_turret_visual_test.tscn` (GLB muzzle/trunnion match the
authoritative ray geometry), `atlas_turret_input_test.gd` (real preview →
wire → servo → reticle, tank buttons), native `atlas_turret_showcase.tscn`
(Foundry practice: the cannon hits the low practice target and plasma bolts
land), `atlas_assembly_test`, `menu_profile_test`, `scorpion_input_test`,
`minigun_physics`, `baseline_smoke`. Before the latest rebase, the MVP suite
passed 48/51. `five_v_five_rules`, `stress_smoke` and `ffa_disconnect`
failed identically on the untouched base 531f15a.

## Open

- A: a matching hosted release (catalogue 11, protocol 8, mvp-ab-18) is
  required before online play. Recorded weapon audio is optional; the current
  sounds are procedural placeholders.
- B (#36): the plasma effects/sound rework and dual/quad upgrade guns
  requested by the user; human playtest acceptance of the tank controls.
