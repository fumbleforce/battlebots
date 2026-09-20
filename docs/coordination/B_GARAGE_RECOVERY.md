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
