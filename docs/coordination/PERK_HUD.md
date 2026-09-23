# Nitro and charged-jump HUD — 23 September 2026

Issue [#9](https://github.com/fumbleforce/battlebots/issues/9), session
`perk-hud-codex-x3d-20260923-1500`, branch `codex/b-perk-hud`.

## Presentation

The integrity/heat instrument now includes two compact status rows. Nitro shows
ACTIVE or IDLE. Jump shows CHARGING, MAX CHARGE, published cooldown seconds, or
IDLE. Both explicitly distinguish NOT EQUIPPED, ROUND LOCKED, OVERHEATED,
DISABLED and UNAVAILABLE; Nitro also reports DRIVE DISABLED when both published
pods are destroyed. These states have text, so color is supplementary. Existing
Barlow typography, instrument housing, accessibility palettes and high contrast
are retained, with no animation or flashing added.

The existing `HudJumpGauge` remains above the resource instrument. It displays
force percentage/MAX while charging and drains with the published cooldown.
Its caption now distinguishes JUMP FORCE from JUMP COOLDOWN. CombatHud owns its
layout and accessibility, replacing the separate MenuGame setup. Missing,
unequipped, overheated, eliminated and round-locked data hide stale force bars.

## Contract

`CombatHud.render` accepts an optional final `perk_parts: Dictionary` containing
the current viewed bot's loadout part IDs. MenuGame passes this only when its
local source and displayed view have the same entity ID. Missing metadata means
UNAVAILABLE, not an inferred installed perk. New views after a pickup or reset
are rendered without retaining earlier equipment/activity.

BotView, BotCommand, snapshots, physics, catalogue and compatibility versions are
unchanged. Both local and decoded remote views use the same renderer. No local
countdown is invented, and the HUD never writes into the supplied view/loadout.
Zero jump cooldown says IDLE: BotView does not certify grounded launch eligibility.
The normal controls remain responsible for commanding Nitro and jump.

## Validation

Pinned Godot 4.7.2 checks:

- Baseline import/smoke passes.
- `perk_hud_test.gd` passes real local and decoded-wire BotView producers,
  unavailable/thermal/round/elimination/drive gates, cooldown/charge/reset,
  unknown equipment, malformed numbers and palette/high-contrast transitions.
  It also verifies the actual MenuGame Practice composition and reset/leave flow.
- Existing combat HUD, jump gauge and composed compact HUD tests pass.
- Composed geometry passes 720p, 1080p and ultrawide at 100/125/150% text,
  including charging, cooldown, captions and simultaneous component failures.
- Native compact HUD captures pass the same size/text matrix. The 720p/150%
  active and cooldown displays were visually reviewed.

The local/remote HUD fixtures author combat values to isolate presentation;
they do not claim natural perk physics or human control-feel acceptance.
The presentation runner includes the new regression. This change requires no
new wire or gameplay release; main's normal automated release workflow still runs.

Additional composed menu/text and audio-caption layout checks pass. The broader
`practice_menu_test.gd` still fails its hidden target-panel 720p bounds assertion:
`[P: (1419, 261), S: (465, 232.5)]` against `(1280, 720)`. The identical failure
and four ObjectDB shutdown warnings reproduce in a separate untouched `70dcc58`
worktree. This predates #9; no target-panel geometry or test gate was changed.
