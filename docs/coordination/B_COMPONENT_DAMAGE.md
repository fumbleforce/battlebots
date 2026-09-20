# Component damage visuals — B implementation

Branch `codex/b-component-damage`, rebased onto main `dfc7dd5`. Implements GAME_SPEC section 9
recognizable intact/damaged/disabled weapon and left/right drive presentation.
Use authoritative BotView.zones (drive 100, weapon 140 maximum) and elimination;
missing/invalid data is unknown, not invented damage. No event history dependency.

B reserves a reusable damage presentation component/shader, Sawblade/Walker visual
component mapping, MvpBot/classic presentation integration, independent fixtures
and docs. All cosmetics: no collision, health, drive force, hit shape or wire/API
changes. A's audio/menu/networking/world remain unchanged. Restore original paint
and visibility on repaired/new-round snapshots; no cross-bot material mutation.

Localized scorched/cracked surface staging plus bounded cosmetic smoke at
failed components. Cover authored wheels, tracks, walker and all weapons plus
classic fallback. Validate stage boundaries, malformed/missing snapshots, component
and instance isolation, restore/reset behavior and native follow-distance views.

## Behavior and integration

`BotDamageVisual.bind_component(zone, meshes, anchor)` owns one overlay and a
six-particle smoke emitter per component. `show_state(BotView)` reads current
integrity only: above 50% intact, positive through 50% cracked/scorched, zero
disabled with stronger scorch and smoke. Elimination disables all bound components.
Missing, nonnumeric, nonfinite and out-of-range values restore the original overlay.
Repair, reset, rebind and removal restore original materials without editing shared
resources. Emitters follow the body anchor in world space with world-up emission;
missing/freed anchors suppress smoke, including before the first frame.

SawbladeVisual/WalkerLegs `component_meshes()` returns fresh arrays for `weapon`,
`drive_left` and `drive_right`, excluding body armor/exhaust and unequipped modules.
MvpBot consumes one current view per rendered frame for weapon and damage visuals.
Authored bodies cover all five weapons and four drives. Legacy box builds have
cosmetic side housings; their existing physical shapes are unchanged. Native
clients consume accepted remote snapshots; no event replay is needed after joining.
Headless authority creates no damage presentation. No catalogue or wire revision.

## Validation (Godot 4.7.2 stable)

- Baseline passes with exit 0. The earlier intermittent shutdown access violation
  remains an unresolved separate observation, not a claimed fix here.
- `component_mesh_mapping_test.tscn`: all 20 authored combinations, visible equipped
  membership, correct sides, no duplicates, walker joints and animation stability;
  headless/native pass.
- `component_damage_test.tscn`: thresholds, malformed snapshots, isolation, original
  overlay restoration, null views, rebind/removal, particle bound, transformed and
  removed anchors; headless/native pass. Both scenes run in check-presentation.ps1.
- `component_damage_runtime_test.tscn`: native actual MvpBot local/remote damage,
  elimination and round reset across authored/classic weapons and walking/wheeled
  assemblies; verifies overlays, smoke and unchanged collision counts. Run with
  `Godot --path battlebots res://tests/presentation/component_damage_runtime_test.tscn`.
- `all_body_weapons_test.tscn` passes. Native damage fixture `-- --capture` produces
  intact/damaged/disabled views at six meters for tracks/saw, wheels/hammer and
  walker/lifter. Reviewed broad surface stages and mechanism-local wisps.

This increment supplies persistent component stages. It does not complete the
spec's sparks, limited fragments, ten-bot performance/LOD targets or human gameplay
readability acceptance. Those remain on B's broader art/combat acceptance work.
