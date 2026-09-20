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
