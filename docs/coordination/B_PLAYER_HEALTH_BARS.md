# Player name health bars — requested HUD handoff

Branch `codex/b-player-health-bars` from main `7026da6`. The user explicitly requests
a fixed-size bar beneath player names, green remaining HP and red missing HP, with
green receding toward the left as damage increases. B coordinates this narrow
change to A-owned BotWorldMarkers and its tests; no general menu, world, networking,
combat rules or health calculation changes. The other local developer is notified.

Consume existing detached BotView.core_fraction. Keep billboard/depth testing and
existing identity/lifecycle behavior. Invalid health data must not invent HP.
Independent scene covers colors, fractions, fixed dimensions, per-player isolation,
accessibility and cleanup; existing real-game marker fixture validates composition.

The bar uses a fixed 128 by 12 texture with a dark two-pixel border, a green fill
anchored to the left and red remainder. The full sprite never resizes with HP,
distance or text scaling; its offset follows text size to remain below the name.
Both colors stay green/red under palette changes, as requested. Arena depth testing
matches the existing labels. Invalid fractions hide the bar until a valid view
arrives; elimination does not invent zero core HP for non-core elimination reasons.
Each player owns its texture, updated only when its displayed fill width changes.

## Validation — Godot 4.7.2 stable

- Baseline and original independent world marker checks pass.
- New `player_health_bars_test.tscn` passes headless/native: full/half/zero colors,
  border and fixed dimensions, invalid values, player isolation, unchanged texture
  reuse, text scaling through 150%, transformed parent and removal. Registered in
  the presentation runner. Native captures at 6m/18m confirm fixed apparent width
  and placement below labels at 100%/150% text.
- Extended `world_markers_game_test.gd` passes headless/native: actual practice
  damage produces 75% local and 50% target bars; reset restores full green. Movement,
  menu suppression and leave cleanup remain covered. The fixture temporarily stops
  the keyboard adapter while submitting its own driving commands to avoid two input
  producers fighting; production controls are unchanged.
- Native GPU readback verifies texture updates. Godot's headless dummy renderer
  retains the initial image on update, so headless checks verify freshly initialized
  full/half/zero pixels and updated fill state; native tests cover changed pixels.
- Native practice exits cleanly. Headless practice still reports two ObjectDB
  instances at shutdown; this observation is not claimed fixed by the HUD change.

No wire/content revision or save migration. The current user-launched test process
is left on its existing checkout; the next launch from updated main includes bars.
