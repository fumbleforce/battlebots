# Practice drones

Original Blender 5.2 assets authored for the Scorpion practice encounter:

- BULWARK: pale ceramic/steel calibration wedge with a forged lifter and four beadlock wheels.
- RAMMER: crimson mobile bruiser with a six-tooth vertical spinner and four heavy treaded wheels.
- WATCHDOG: petrol-blue tracked sentry with a six-barrel minigun, linked brass rounds and a removable receiver.

Run `blender --background --python art_source/practice_npcs/generate_practice_npcs.py` from the repository root. It creates the three packed `.blend` sources beside this file and portable GLBs/material maps under `battlebots/assets/models/practice_npcs/`.

Source coordinates fit a 1.6 x 0.5 x 2.0 meter canonical hull. Runtime fits that hull once to the catalogue dimensions; source meshes must not be enlarged separately. Paint has original 1024px enamel/wear albedo, roughness/metalness and subtle micro-normal maps. Machined edges use applied bevels and weighted normals. Rubber, steel, brass, optics, fasteners, cooling fins and individual track/tire lugs are separately surfaced.

Named `Detach_Weapon_*`, `Detach_Drive_*` and `Detach_Armor_*` meshes are complete physical-looking assemblies with their original materials and local pivots. `PracticeNpcVisual` maps weapon/left/right drive damage and wheel/spinner/minigun motion. `BotDestructionVisual` copies up to eight actual meshes into its existing bounded cosmetic debris pool, hides attached counterparts and restores them on repair. There is no debris collision or client damage authority.

The offline `PracticeBotDirector` creates canonical loadouts before assembly, tags appearance privately, submits ordinary `BotCommand`s and preserves the first calibration entity for `practice_target()`. Wrecks regenerate after six seconds only when their original spawn is clear; the player and weapon event clock are untouched. Restart resets pilots; leave destroys the director; online sessions never create it.

Validation scenes/scripts:

- `tests/practice/practice_npcs_test.gd`: actual movement and authoritative sentry hits, bounded spawn count, stable replacement, occupied spawn, restart/leave and online exclusion.
- `tests/presentation/practice_npc_visual_test.tscn`: damage groups, exact detached geometry/world transforms, original-material retention, debris budget, expiry/restoration and native lineup/explosion screenshots.
- `tests/presentation/practice_natural_destruction.tscn`: normal Scorpion aiming/fire commands destroy the full-health calibration NPC through real Jolt combat; native evidence capture uses the genuine destruction event.

The deterministic lifecycle fixture explicitly sets damage to exercise reset/respawn; the natural destruction fixture never changes health, damage values or loadout budgets.
