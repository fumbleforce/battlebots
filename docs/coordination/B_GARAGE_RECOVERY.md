# B garage disk recovery

Intent to A: `codex/b-garage-recovery` starts from main `e24ab02`.
B reserves LoadoutStore, PlayerProfile, garage/customize recovery controls and
independent storage/UI scenes. No general menus, session, world or wire changes.

Implement an explicit reload that retains edited and new drafts as unsaved
copies while refreshing disk slots. A stale draft must never overwrite a newly
loaded external build. Backup recovery requires explicit review/confirmation,
unchanged source fingerprints and preservation of the broken primary bytes.
Do not reset unreadable saves or silently write fallback data.

Subagent owns store recovery API and isolated file tests; primary owns profile,
recovery panel, composed scene checks and documentation. Validate cancel,
changed sources, malformed siblings, retained drafts and successful post-recovery
save. Run pinned Godot baseline and garage regressions before main integration.

Implemented: Saved File entry on Garage and Customize, read-only backup review,
explicit confirmation/cancel and result with preserved-primary archive path.
Reload retains modified/new drafts as named unsaved copies; unchanged builds keep
their history on an exact disk match. History without a disk match is detached,
including redo at baseline. Retained copies append only; stale indices cannot
replace external edits. Backup fallback blocks Save until explicit restoration.
No readable backup means refusal, never a file reset.

Independent review found modal directional-focus escape, missing initial Garage
focus and redo-at-baseline loss; all three are fixed and covered in the actual
screen fixture. Stale equip/buy and concept-art labels were removed from touched
B code. Current handoff/backlog and local contracts now describe recovery.

Validation (Godot 4.7.2): LOADOUT RECOVERY and GARAGE RECOVERY scenes pass;
the latter also passes D3D12 rendered at 1280x720 with inspected review/result
captures. Checks cover cancellation, changed-source rejection, exact primary/
backup/archive bytes, malformed siblings, absent primary, retained active draft,
Undo/Redo, repeated reload, keyboard focus and saving after recovery. BASELINE,
MENU PROFILE, GARAGE HISTORY, GARAGE REPAIR, LOADOUT REPAIR, GARAGE COMPARISON PANEL
and MENU CUSTOMIZATION SCREENS pass. Scenes are registered in the presentation
runner. Disk-full/OS rename failures are handled but not fault-injected; no
cross-process filesystem lock is claimed. Text scaling/art/gameplay remain open.
