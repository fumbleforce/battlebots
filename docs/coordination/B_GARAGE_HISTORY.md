# B garage edit history

Owner B; branch `codex/b-garage-history`; base `origin/main` at `2b42812`.
Scope: PlayerProfile draft history, customization controls, independent garage
tests and B handoff. No general menu/router, combat, network or world edits.

Implement per-build undo/redo for parts, paint and committed name edits. Preserve
invalid drafts for repair, isolate histories across builds, bound memory, retain
history when navigating the catalogue and clear it on profile reload. Undo/redo
never writes saved loadouts; Save remains explicit. Existing record/schema and
catalogue identities stay unchanged.

Acceptance: no-op equip preserves redo; a new edit discards its redo branch;
invalid combinations undo back to legal builds; histories never cross builds;
failed saves preserve disk/history; successful saves do not become implicit
undo writes. Buttons/shortcuts work with safe text-field focus and fit 1280x720.
Register the new fixture alongside existing garage/profile checks.

Completed: buttons under the build preview and Ctrl+Z/Ctrl+Y/Ctrl+Shift+Z.
Text fields retain their native undo; Enter or leaving the name field commits
one name edit. Histories retain the latest 100 edits per build across local menu
navigation and Save, and are discarded on profile reload. No save schema change.

Validation: Godot 4.7.2 baseline, garage_history_test, menu_profile_test and
menu_customization_screens_test all passed with clean exits. The new fixture also
passed with D3D12 rendering; the 1280x720 customization screenshot was inspected.
The test is registered in check-presentation.ps1. General menu, combat and
network implementations are unchanged. Live 3D preview, detailed comparisons,
full repair UX and garage accessibility scaling remain open B work.
