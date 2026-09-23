# Atlas MX turret — B, 23 September 2026

Design lessons (looks, sound, recoil, checklist for new parts):
[WEAPON_FEEL.md](../art/WEAPON_FEEL.md).

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

- Catalogue revision 11 (first turret release) and revision 13 (upgrades) and revision 14 (hash `243e5508261cbfc210967638b9466614665689bf85ed82bc0897ebc5f827cb73`, special turrets) adds utilities `turret_cannon`
  (16 kg/25 power) and `turret_plasma` (14/25). They are Atlas-only and
  exclude the primary minigun. Revision-10 to revision-13 saves migrate. Preset
  `ContentRegistry.atlas_turret()` is seeded as the sixth profile preset.
- `BotCommand`: `aim_valid` (flag bit 9), `aim_yaw`, `aim_pitch`
  (world bearing and elevation from the trunnion). The wire command array
  has 6 fields. Snapshots append `turret_yaw` (40 fields). Elevation reuses
  `gun_pitch`; shots reuse `shot_sequence`/`last_shot_*`. **PROTOCOL 10,
  BUILD mvp-ab-24** (catalogue 13 with the upgrades; main's shared-heat change took 9/19–21 meanwhile).
- Server (`CombatWorld`): the servo slews toward the aim at 1.9/1.2 rad/s
  within the audited elevation profile, elevates before traversing, and is
  stabilised against hull motion. Rays run from the trunnion along the actual
  barrel. Walls and allies occlude. Cannon: 32 raw, 2.4 s reload,
  16 shared heat. Plasma: 11 raw per bolt every 0.22 s, 4.5 shared heat.
  Event kinds are `cannon`/`plasma`.
- Controls (B): turret builds view through `TankSightCamera`, which uses the
  rig's mouse state from a sight point above the turret. LMB fires the main
  gun, RMB operates the hull weapon. `TurretReticle` shows the crosshair,
  the actual barrel point and reload.
- Presentation: `TurretShotEffects` (recoil, flash, travelling
  projectile, lit billow smoke plus fog volumes, first-pass procedural
  reports in the `bot_action_audio` group).

## Upgrades: twin and quad guns (catalogue 13)

At the user's request, catalogue 13 adds `turret_cannon_dual` (22 kg/35),
`turret_cannon_quad` (30/40), `turret_plasma_dual` (20/35) and
`turret_plasma_quad` (28/40). The user asked for both Customize selection
(budget-limited: quads need light armor) and #35 in-match pickups. Pickups
draw them from the ordinary catalogue pool; weighting them rarer would change
#35's file and is not done.

Models: the generator derives each multi-barrel attachment from the approved
single weapon (cross-section scaled copies with a cast cradle block). It
exports `Attachment{Cannon|Plasma}{Dual|Quad}`, `CannonRecoil{Dual|Quad}_i` and
`Muzzle{Cannon|Plasma}{Dual|Quad}_i`. The audit profiles all six attachments;
the quads have less flank depression. `tools/update-turret-geometry.py`
regenerates `AtlasGeometry.TURRET_DEPRESSION`/`TURRET_BARRELS` from the
manifest.

Rules: the barrel of a shot is `(shot_sequence - 1) % barrels`, so no wire
field is added. Cannons ripple a volley one barrel every 0.09 s, then reload
(2.6 s twin, 3.0 s quad; 11/9 shared heat per shell, 32 raw each).
Plasma alternates barrels every 0.13 s (twin) or 0.075 s (quad, 5 ticks =
12 bolts/s), 4.0/3.4 shared heat per bolt, 11 raw each. Each ray starts
at its own barrel's breech. Presentation recoils the barrel that fired.
Turret and reticle angles are predicted between authoritative samples and
eased, so both move smoothly at any frame rate.

## Feel, quad sponsons and special turrets (23 September, catalogue 14)

User playtest feedback, all implemented:
- **Cannon feel.** Each shell applies a real firing impulse at the muzzle plus
  a rocking torque impulse across the shot on the server. Measured on flat
  ground: about 6–8° for one shell, 12–15° for a twin volley and 18–23° for a
  quad volley, settling within about 1 s. No further rock is added past 10° of
  tilt, so a volley cannot flip the hull. The tank sight kicks and shakes on
  own shots. Shells are larger, with a riding light and a smoke trail. Impacts
  have a fireball, blast light, shockwave ring, sparks, a smoke column and a
  scorch. Report/detonation sounds are saturated low booms with a crack, a
  rumble and a breech clank. The plasma sound was lowered and made punchier.
- **Quad guns** sit in armored sponsons that are part of the turret casting
  (`SponsonsQuad`, shown only for quads). Two stacked barrels per side on
  compact trunnion cradles. Outboard barrels converge on the point the centre
  bore line strikes, so they land where the reticle shows. Trade-off: quads
  depress only about −2° on the flanks (−14…−16° over the nose).
- **Special turrets** (Atlas utilities, audited and modelled):
  `turret_flamer` (15/25): a 17 m cone pulsed every 0.1 s, 4 raw per tick
  to every visible enemy inside it; walls shorten the jet. `turret_tesla`
  (16/30): every 0.55 s it arcs 18 raw to the nearest visible enemy within
  15 m / 40° and chains 9 raw to a second enemy within 9 m.
  `turret_railgun` (20/35): hold 1.1 s to charge and release to fire; 70 raw,
  140 m, pierces into a second target for half; an early release cancels;
  1.6 s reload and a heavy jolt. All use shared heat and the existing shot
  fields (no wire change); event kinds are `flamer`/`tesla`/`railgun`.
  `TurretSpecialEffects` draws the fire jet, smoke and roar, the lightning
  arc and zap, the rail charge glow and whine, and the beam and report. The
  Tesla chain is shown only through confirmed hit sparks.
- Tuning lives in `data/turret_weapons.json` (typed `TurretTuning` loader),
  per the repository rule against bare tuning numbers in logic.
- Seeded presets: ATLAS MX • FORTRESS (quad cannon), INFERNO (flamethrower +
  saw) and RAIL (railgun). `PlayerProfile.PRESET_COUNT` is 9.

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

- A: a matching hosted release (catalogue 14, protocol 10, mvp-ab-24) is
  required before online play. Recorded weapon audio is optional; the current
  sounds are procedural placeholders.
- B (#36): the plasma effects/sound rework and dual/quad upgrade guns
  requested by the user; human playtest acceptance of the tank controls.
