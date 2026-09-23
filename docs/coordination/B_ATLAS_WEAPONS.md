# Atlas MX grab, lob and front-tool weapons (#52–#56)

User request (23 September 2026): a harpoon to tug enemies in, a stab
spear/forklift that impales and grabs, a physical ram, a mortar aimed from a
high view in front of you (a camera per weapon), and a huge spiky grinder on
thick arms. The user asked for Atlas MX compatibility first. Look, sound and
feel follow [docs/art/WEAPON_FEEL.md](../art/WEAPON_FEEL.md).

| Weapon | Part (slot) | Model | Verb |
|---|---|---|---|
| Harpoon (#52) | `turret_harpoon` (utility) | `AttachmentHarpoon` in `atlas_turret.glb` | press: fire a barbed bolt on a cable; hold: winch the target in; press again: cut |
| Mortar (#55) | `turret_mortar` (utility) | `AttachmentMortar` in `atlas_turret.glb` | aim a ground point in the artillery view; press: lob a shell over walls |
| Battering ram (#54) | `battering_ram` (weapon) | `ToolRam` in `atlas_tools.glb` | passive prow multiplier; press: hydraulic punch |
| Spear/forklift (#53) | `spear_fork` (weapon) | `ToolSpear` in `atlas_tools.glb` | press: thrust and impale; hold: lift and carry; release: throw off |
| Grinder drum (#56) | `grinder_drum` (weapon) | `ToolGrinder` in `atlas_tools.glb` | hold primary: spin and shred; hold secondary: raise the arms |

All five are Atlas MX only. The turret parts use the roof race (#36). The front
tools bolt to the existing quick-release coupler.

## Contracts (protocol 12, catalogue 16)

- The snapshot gains three fields, 43 in total:
  - `grip_target`: an entity id, 0 when nothing is held.
  - `grip_point`: the world anchor on the victim.
  - `tool_pose`: 0..1, the spear carriage lift or the grinder arm raise.
  The first two are a generic, replicated **grip**. `CombatState.grip_mode`
  (server only) records whether the harpoon or the spear holds it. A spear
  impale takes precedence. The harpoon neither fires nor cuts while the spear
  holds a target.
- `gun_pitch` may reach 1.45 rad because the audited mortar cradle stops at
  80° (`AtlasGeometry.TURRET_PITCH_MAX_BY`).
- The mortar needs no new command field. Its `aim_pitch` is the world launch
  elevation of the steep arc, and range follows from elevation because muzzle
  speed is fixed. `AtlasGeometry.mortar_elevation` computes that elevation for
  the gunner. `mortar_flight`/`mortar_point` give the presentation the same
  arc from `last_shot_from`/`last_shot_to`.
- Ram-punch, spear and grinder hits are new combat event kinds: `ram_punch`,
  `spear`, `grinder`. Audio and impact visuals map them to the ram, hammer and
  saw cues.
- Tuning:
  - Harpoon and mortar: `data/turret_weapons.json` (`TurretTuning`).
  - Front tools: `data/front_tools.json` (`FrontToolTuning`).
  - Tool geometry: `AtlasGeometry` `RAM_*`, `SPEAR_*` and `GRINDER_*`, from
    `atlas_tools_manifest.json`.

## Rules

- **Harpoon.** The server ray anchors the bolt where it strikes an enemy.
  - While the trigger is held, a winch drives the line in toward `reel_speed`,
    capped at `pull_acceleration` × heft. It eases off over the last metres
    and stops at `min_length`. `reaction_share` of the pull drags the shooter.
  - The cable snaps past `max_length`, when static geometry cuts the line,
    after `max_seconds`, or on elimination.
  - A spring or unlimited pull fired the target into the shooter and shoved
    both 20 m. The speed-limited winch fixed that.
- **Mortar.** The server flies the shell along its real ballistic path with
  30 Hz swept rays (`CombatWorld.mortar_trace`, shared with the gunner's
  marker). It detonates at the first contact after the actual flight time.
  - Damage falls from `damage` at the centre to `blast_edge_share` at
    `blast_radius`, and walls shield.
  - Elevation runs from `min_elevation` (45.8°) to 80°, which gives about
    20–60 m of range on flat ground. Targets closer than that can't be hit;
    this trade-off is intentional.
- **Ram.** A ram contact within `front_cone` of the prow multiplies the ram
  damage (×2.2) and knock-back (×1.6). The rammer takes `self_share` (0.35) of
  the return blow. The #50 wall pin still applies.
  - The punch strikes each target the extending prow reaches once per press.
- **Spear.** The thrust pierces the first enemy the blades reach: an intact
  plate stops only `armour_share` of the damage. The target is impaled.
  - Holding primary keeps it on the tines with a capped spring-damper, lifts it
    with the carriage and staggers its drive.
  - Letting go throws it off. It tears free past `strain_distance`, after
    `max_hold_seconds`, or when the weapon is disabled or overheats.
- **Grinder.** Spin charge builds while primary is held.
  - Drum contact grinds every `cadence` seconds; armour plates take
    `plate_multiplier` × damage, and contact pulls the target in.
  - Secondary raises the arms over `raise_seconds` to put the drum on top of
    the target. With a turret fitted, secondary is taken by the hull weapon,
    so the arms stay down.

## Controls and camera

- **Mortar:** switches the tank sight into `TankSightCamera.artillery`, a high
  camera above and behind the hull looking steeply ahead.
  - Mouse yaw turns the bearing, and mouse pitch walks the screen-centre
    ground point between near and far.
  - `MortarAimVisual` draws the arc a shell fired now would fly, ending in a
    blast-radius ring. It is amber while reloading, bright when ready, and red
    when the target is out of reach.
- **Harpoon:** uses the ordinary tank sight.
- **Front tools:** use the primary (and secondary) weapon buttons, as the
  lifter does.

## Presentation

- **Harpoon** (`TurretHarpoonEffects`): the loaded head leaves the tube, and a
  barbed bolt pays out cable. The cable sags when slack and hums taut while
  reeling. There are thoonk, clang, twang and winch sounds.
- **Mortar:** the cannon shot effects are lobbed along the real arc. The
  detonation is 1.7× larger, but its sparks stay gun-sized; enlarged sprites
  read as glowing balls. A falling whistle starts 1.3 s before impact.
- **Front tools** (`AtlasToolVisual`): drives `RamPunch`, `SpearCarriage`,
  `SpearTines`, `GrinderArms` and `GrinderDrum`. It plays hydraulic slams and
  a spin-pitched grinding roar, and the drum throws sparks while grinding.

## Models

- **Turret attachments.** `tools/build-atlas-turret.py` builds the harpoon: a
  gas breech over an air bottle, an open launch tube and a cable fairlead with
  rollers. The side winch carries wound cable, and the barbed head sits
  loaded in the tube. The mortar is a thick-walled bored tube with a ribbed
  breech, recoil buffers and a ready rack.
  - The clearance audit sweeps the mortar to its 80° stop.
  - `tools/update-turret-geometry.py` regenerated the tables.
- **Front tools.** `tools/build-atlas-tools.py` (helpers in
  `tools/atlas_model_kit.py`) builds all three on one coupler backing plate at
  Z=−1.42. That is in front of the optional chin armour and the track noses;
  the first draft at −1.37 clipped the chin plate.
  - The generator audits each tool at rest, half and full travel against the
    hull and every optional module. The result is clear.
  - Review renders are in `art_source/atlas_tools/`.

## Validation (Linux, Godot 4.7.2)

- New suites:
  - `tests/simulation/atlas_launcher_physics`: harpoon hit, cut, ride, snap,
    wall cut and miss; a real-Jolt reel from 28 m to 16 m in 3 s without
    shoving the shooter; mortar servo, lob over a wall to the aimed point,
    delayed blast and radius.
  - `tests/simulation/atlas_tools_physics`: ram 12 → 26 damage dealt with
    only 4 taken back; the punch shoves a target 7.4 m; the spear impales,
    lifts, carries and throws; the grinder shreds a plate and builds heat.
- Updated: `atlas_turret_physics` (the 120 kg budget check was retired by #49),
  `atlas_assembly_test` and `scorpion_input_test` (new snapshot bounds).
- Suites run: turret visual and input, menu profile, garage history, catalogue
  text, customization, pickup, combat impact, heft, rules, content, and the
  scorpion and hammer sessions.
- `tests/network/session_smoke` also fails on untouched `origin/main`
  ("Next round repairs and starts").
- Native evidence: `tests/presentation/atlas_weapons_showcase` in Foundry
  practice. The harpoon tethers the dummy, the mortar blast damages it, and
  the ram, spear and grinder damage it.

Human playtest acceptance is still open.
