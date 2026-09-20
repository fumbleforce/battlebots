# B garage repair persistence

Intent to A: `codex/b-garage-repair`, based on main `331e073`. B reserves
LoadoutStore, PlayerProfile, Customize repair controls and independent B scenes.
No general-menu/network/combat/world changes. Subagent owns targeted store API
and isolated storage tests; primary owns profile/UI and handoff.

Observed defect: Save rebuilds the saved array from disk snapshots and rejects
every invalid sibling. With two invalid entries, neither can be saved after
repair; edits to the other in-memory draft do not resolve the loop.

Add local `LoadoutStore.save_build(draft, index, expected)` to validate one saved
replacement while retaining every untouched invalid/malformed entry. Reject
stale external edits, corrupt envelopes, invalid replacements, duplicate names
and full capacity. Existing strict `save(Array)` and wire loadout schema stay.
Profile uses the targeted API. Explicit revalidation updates only draft format/
catalogue metadata; selected part IDs and paint are never silently substituted.
It is undoable and writes nothing until Save succeeds.

Acceptance: independently reproduce and fix sequential repair of multiple bad
entries; preserve malformed siblings and files on failures; test actual Customize
repair/Save/Undo and unknown content versions; run baseline/garage regressions.

Completed: targeted saves preserve raw sibling records, including malformed and
compatible legacy entries. Expected baselines normalize JSON number types to avoid
false stale conflicts after in-memory integer edits. Strict save remains strict;
both paths enforce the existing 64 KiB read limit on writes and check flush errors.
Customize exposes undoable Revalidate only for an outdated/unsupported envelope.
Rapid redraw focus is guarded against removed controls, fixing a reproduced GUI
error in the independent repair fixture.

Validation: Godot 4.7.2 loadout_repair_test and actual garage_repair_test scenes
pass; rendered invalid and repaired screens reviewed at 1280x720. Store coverage
includes sequential repairs, malformed/legacy siblings, append, stale/invalid/
duplicate/capacity/size rejection, recovery refusal and original-byte backups.
Baseline, CONTENT, profile, history, comparison panel and customization checks
pass. The old profile test now asserts successful append plus exact invalid-sibling
preservation instead of expecting the former blocking behavior. Independent scenes
are registered in the presentation runner. Corrupt-file/backup confirmation and
stale-file reload UI remain open; these cases safely refuse writes for now.
