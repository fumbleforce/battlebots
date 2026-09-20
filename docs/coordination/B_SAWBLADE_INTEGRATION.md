# Sawblade Tank integration — B, 20 September 2026

Branch: `codex/b-sawblade-integration`, base `9e54dcc`.

Scope: export the existing Blender source to a portable runtime model, assemble
its modules in garage/gameplay, and expose all eleven root custom properties.
Owned paths: bot assets, presentation, garage/profile and bot loadout validation.
Shared handoff: optional validated `cosmetics.sawblade` record; existing part IDs
remain authoritative. Saw/hammer/ramp map to saw/hammer/lifter. Drive appearance
supports tracks and wheels; armor covers/exhaust/paint are cosmetic, not additional
damage protection or performance. Existing loadouts remain readable.

Validation planned: portable import/baseline, independent module and malformed
loadout tests, profile persistence/history, garage preview, and rendered inspection.
The source blend and unrelated local project/import edits must be preserved.

First increment: portable GLB plus sampled authored hammer/tread tracks, shared
four-channel shader, garage vehicle/module/color controls, profile save/history,
and gameplay presentation. Hammer primary uses the existing rebound primary
action; authored frames 1–9 align with windup, 9–12 hold impact, 12–33 return
over authoritative cooldown. No client animation applies damage.

Godot 4.7.2 baseline and sawblade, legacy preview, repair, recovery, catalogue
text and history checks pass. Model rendered in Compatibility. Walking legs are
the user's additional requested second increment, including physical climbing;
not implemented by this first commit. Final content identity/online handoff must
cover the new appearance contract and walking drive together.
