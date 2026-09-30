# Weapon mounts: every weapon on every offered body (#108)

User request, 30 September 2026: all weapons should be compatible with all
available chassis. Issue: [#108](https://github.com/fumbleforce/battlebots/issues/108).

Before this, four groups of weapons were tied to a body by
`ContentRegistry.validate`: the front tools (battering ram, spear · forklift,
grinder drum) and the eleven turrets to the Atlas MX, the auxiliary minigun to
the Atlas MX or Scorpion, and since #109 the Ramp to the Sawblade body and the
Lifter to every other body. Now every Weapon 1 and Weapon 2 part validates on
every body Customize offers: the Sawblade body, the Scorpion hex body and the
Atlas MX.

## What changed

- **Validation.** The body rules are gone. Two rules remain because the
  weapons share one mechanism, not because of the body: a turret excludes the
  primary minigun, and one build carries one minigun. Drive rules (Scorpion
  legs, Atlas running gear) and the 100 power budget are unchanged.
- **Mounts.** `battlebots/data/weapon_mounts.json` (loader
  `scripts/core/weapon_mounts.gd`, referenced by `preload`) records, per body,
  where the Atlas-authored weapon sits: a uniform scale and an offset for the
  turret race and for the front tool coupler, plus an offset for the auxiliary
  gun. Bodies: `sawblade` (any wheeled or tracked body drawn as the Sawblade
  tank), `scorpion`, and `box` (the plain placeholder hull used by tests).
  The Atlas MX and Bracken use no mount (identity).
- **Authority.** `ContentRegistry.validate` publishes `turret_mount`,
  `tool_mount` and `turret_depression` in the stats. `CombatWorld` maps every
  Atlas-frame turret and tool point through them (muzzle, breech, harpoon
  line, ram/spear/grinder volumes, spear hold point) and scales lengths by the
  mount scale. Tuning (damage, heat, range, cadence) is the same on every body.
- **Presentation.** `scripts/presentation/mounted_weapons.gd` draws the turret,
  front tool and auxiliary gun on the mount frames, beside the body's own
  visual, in `MvpBot` and the garage preview. The turret logic moved out of
  `AtlasVisual` into `turret_module_visual.gd`, which both use. The modules
  take the body's paint layers. `BotView.turret_mount` lets the aim, reticle
  and mortar marker follow the mounted turret.
- **Ramp and Lifter.** #109 split the lifting tool into two named weapons and
  bound each to a body. Both now fit every body. The Ramp keeps its Sawblade
  size and is hinged just ahead of another body's front face, as high above the
  ground as on the Sawblade (`SawbladeGeometry.ramp_hinge` / `ramp_volume`,
  the same rule #109 uses for the shared saw); its chassis braces and hydraulic
  ports are hidden there. The Lifter on the Sawblade body is the ordinary
  lifter arm. A body change keeps the fitted tool. Builds from before the
  split still become the Ramp they showed
  (`ContentRegistry.keep_presplit_ramp`, also in `LoadoutStore.migrate`, which
  now migrates catalogue 19 saves).
- **Solid weapons (#112).** The rest-pose weapon colliders follow the same
  frames: front tools through the tool mount, and the Ramp's wedge at its hinge
  on any body. On a four-legged walker other than the Sawblade body (the Atlas
  on legs) the Ramp hangs from the crouched ride height, so it reaches the floor
  only while that walker crouches and never digs in.
- **Customize and pickups** follow validation: parts are listed when they fit
  the build, and a body pickup no longer swaps the utility or the lifting tool.

## Where things sit

| Body | Turret | Front tool | Auxiliary gun | Ramp | Lifter |
| --- | --- | --- | --- | --- | --- |
| Sawblade | On the rear pack crown at 63% of the Atlas size; the carry handle is removed | On the chassis deck between the tracks at 68%, joined by two coupler rails | On the right wall of the rear pack, above the track (a primary minigun sits there too; it used to overlap the track) | Its own built-in plate | Lifter arm at the front face |
| Scorpion | On the dorsal deck at 60%, on a short pedestal over the deck fittings, ahead of the exhaust stacks and under the tail | On the lowered tool socket under the nose at 68% (the existing adapter arms) | Its own authored gun mount | Hinged under the nose, reaching the ground | Lifter arm on the lowered tool socket |
| Atlas MX | Authored roof race | Authored quick-release coupler | Authored roof gun socket | Hinged ahead of the lower bow | Authored forged lifter |

Smaller tools reach less far: the Sawblade's ram nose is about 3.4 m ahead of
the hull centre, the Atlas's 5.7 m.

## Barrel clearance

`battlebots/tools/audit_turret_clearance.gd` measures, per body, turret model
and 5° of bearing, the lowest elevation at which the elevating group stays
2 cm (hull source metres) clear of the body's own hull. It sweeps down from
the upper stop and checks the half steps the runtime rule interpolates over.
The hull is the body's visual with every armour and exhaust option fitted and
without the primary weapon, as in the Atlas audit. The result is the
`depression` tables in `weapon_mounts.json`; `AtlasGeometry.turret_pitch_min`
reads them through the stats. Rerun the tool after changing a turret mount
(`-- --check` compares without writing).

Recorded trade-offs:

- **Sawblade.** −20° over the nose and most bearings. The quads reach about
  −13° on the flanks and the harpoon −6° to −8° (its winch sits low).
- **Scorpion.** −20° over the front 270°. The two exhaust stacks stand higher
  than the trunnion, so single and twin barrels must rise to about +20° across
  two 25° sectors at the rear quarters (around 140–165° and 195–220°); straight
  back is clear to about −17°. The quads' sponson guns swing through both
  stacks: most of the rear 150° needs +30°. A Scorpion turret therefore cannot
  engage targets behind its shoulders; the driver turns the hull.
- The servo already raises a depressed barrel before traversing into a bearing
  that needs it, so the turret never clips the stacks.

The primary weapon is not part of the audit (it is not on the Atlas either): a
raised Scorpion tail or a Sawblade saw can cross an elevated or depressed
barrel on screen. Shots are traced from the trunnion and ignore the shooter.

## Power budget

Mounts never refuse a part, but the 100 power budget still does
(GAME_SPEC: mass/power validation remains). The Scorpion's walking drive costs
35, so a quad turret (40) cannot be built on it even with a 30-power weapon
(105). Quads reach a Scorpion only as match pickups, which are exempt from the
budget. Changing that means changing a part's power in the catalogue.

## Reviewing placement without a window

`battlebots/tools/render_bot_review.gd` draws the garage preview's model with a
software rasteriser (flat shaded, orthographic, one colour per material) and
saves PNG files, headless:

```
godot --headless --path battlebots -s res://tools/render_bot_review.gd -- <out_dir> <body> <weapon> <utility> [drive] [modules=...] [view ...]
```

It shows placement, proportion and clipping. It does not show textures,
lighting, effects or animation.

## Validation

- `tests/simulation/weapon_mounts_physics.gd` (in `check-mvp.ps1`): all 10
  primaries and 12 auxiliary weapons validate on the Sawblade, Scorpion, Atlas
  and box; only the power budget can refuse them; ram punch, spear impale and
  grinder contact at each body's mounted reach and not beyond; the Ramp on the
  Atlas, Scorpion and box and the Lifter on the Sawblade flip a target against
  the nose; the cannon fires
  from the mounted muzzle and the servo stops at the measured clearance; the
  auxiliary gun hits from the Sawblade and the box.
- `tests/presentation/weapon_mounts_visual_test.gd` (in
  `check-presentation.ps1`): for every body and turret model the drawn trunnion
  and every muzzle marker match the server geometry at three poses; tools sit on
  the server's tool frame; the garage preview draws and clears the modules.
- `tests/simulation/weapon_collider_physics.tscn` (#112) now checks every melee
  weapon's collider on all four bodies, since every combination validates.
- Updated: Atlas tool/turret/launcher physics, match pickups, garage compatible
  parts, content smoke (lifting tools, catalogue 19 migration), Scorpion garage.
- Placement reviewed in headless review renders only (Sawblade and Scorpion
  with each tool, single and quad turrets, the auxiliary gun, all armour
  modules; the Ramp on the Atlas and Scorpion; the Lifter on the Sawblade).

## Not verified, and limits

- No native capture or play test: effects, sound, recoil feel, the tank sight
  and the reticle on the new bodies have not been seen in game. The windowed
  `MvpBot` path that adds the modules is not reached by headless tests.
- The Lifter is the forged arm only on the Atlas MX; on the Sawblade and
  Scorpion it is still the placeholder fork (as it already was on the Scorpion).
- The Sawblade body's own Ramp only reaches a target that is over its plate
  when it flips (unchanged): on flat ground a target against its front face is
  out of the raised plate's reach. On other bodies the plate lies ahead of the
  hull, so a target against the nose is flipped.
- Legacy hull sizes (`compact`, `wide`) reuse the Sawblade mounts scaled with
  the art; their clearance tables are the ones measured on the offered body.
- On a body with walking legs other than the Scorpion, front tools ride at hull
  height like the other primaries there.
- The factory-sealed builds (Bracken, Strider, Hellwheel, Pogo, Skater) stay
  sealed; their weapons are unchanged (#75 covers the nimble bots).
