# A/B playtest integration

User requested winding down feature work, merging incoming work and preparing
for testing. Planned branch: `codex/a-b-playtest`, based on the FFA increment.
Keep the full game goal open; this is a testing checkpoint, not release acceptance.

## Incoming published work

- `codex/b-match-hud` at `d983612` includes B controls/rebinding, diagnostics,
  lobby and match HUD. `codex/b-match-results` at `0f343f7` adds results-work intent.
- `codex/b-flamebot-art` at `909b666` contains Flamebot runtime GLB and source.
- `codex/b-sawblade-tank` at `5ec8dbb` is an independent Blender-source asset.

Merge committed heads only. Leave the separate modelling checkout untouched.
Preserve A session/rules, including B's numeric JSON team-selection fix alongside
FFA rejection of team changes. Preserve both developers' contract/TODO additions.

B's current standalone frontend supports duel/2v2; A's existing launcher supports
all modes. Keep these separate so each scene has one input/session owner. New B
controls and camera changes are consumed by the existing preview. Do not claim
B's planned results screen exists or silently replace 5v5/FFA with a team-only UI.

Art is merged for inspection, not assigned combat stats or collision. Flamebot
has a Godot runtime export; the saw source still needs an export excluding studio
objects. Exclude that source folder from Godot import until a portable runtime
export is provided, so this checkpoint does not require Blender to run/export.

## Validation

Run baseline/full A regression, B presentation runner, targeted art-import check
and independent process startup on the merged tree. Record actual outcomes and
CI link below. Human two-computer LAN, contact/camera feel, full combat performance
and sustained soak remain open.
