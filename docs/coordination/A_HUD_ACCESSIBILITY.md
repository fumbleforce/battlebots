# A — HUD accessibility

Intent 2026-09-20, `codex/a-hud-accessibility`, base `bd1dd3f`.
A reserves combat/round HUD presentation, new HUD preferences/settings, general
settings composition and independent fixtures. Deliver independent HUD text
sizes through 150%, selectable color-vision palettes and high contrast. Reflow
large text at 720p rather than shrinking the HUD canvas to disguise overflow.
All status meanings remain explicit text, not color alone.

B controls, camera, garage, bot visuals and network schemas remain unchanged.
This HUD increment does not claim complete 150% scaling for all menus or world
markers, nor the deferred input/network ping interface. Keep those acceptance
items open. Validate persistence/cancel/save, rendered layout and in-game
settings integration; document actual limits before merging main.

## Implementation and evidence

- New versioned `HudPreferences` validates size/palette/contrast and bounded
  files, saves atomically and preserves existing files on invalid values.
- Original-theme settings panel has an actual scaled/color sample, keyboard
  navigation and transactional preview/Save/Cancel. The game composes it into
  general Settings alongside Audio without editing B control-settings code.
- Combat/round fonts grow independently from viewport scale; above 100%, panels
  reflow and component integrity uses labelled cells. Exact status, timer and
  resource semantics remain authoritative and color-independent. Practice target
  moves below the left roster; its redundant restart hint hides at larger sizes
  while the game menu retains Restart practice. Captions scale and stay separate.
- Baseline, preferences, settings, detached accessibility and composed-game
  accessibility checks pass with Godot4.7.2/Jolt. Preference tests cover malformed,
  oversized/invalid files and failed saves; panel tests cover preview rollback.
- Rendered native720p/1080p large HUD and four-palette high-contrast views inspected.
  Full practice-game captures `a-accessible-game-1280.png` / `-1920.png` and settings
  `a-hud-settings-720.png` are local Godot user-data artifacts, not release exports.
- Existing combat HUD, match HUD and match layout checks pass. New fixtures are
  registered in the presentation runner. No state producer or gameplay logic changed.
- Composed default HUD and Audio settings regressions pass. Real ENet game
  reconnect also passes after losing transport with an unsaved accessibility
  preview open: it closes the modal, restores preferences and recovers gameplay
  and results. All final parent checks completed without engine errors.

The diagnostic text panel retains its own font sizing. Full-menu 150% text,
world/team markers, reduced-motion coverage and human color-vision acceptance
are not certified by these HUD checks. Ping interfaces and external deployment
remain outstanding. The previous engine shutdown warning is not claimed fixed.
