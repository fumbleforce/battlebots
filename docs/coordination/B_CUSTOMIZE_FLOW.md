# B Customize interaction and layout — 22 September 2026

Owner: B. Branch: `codex/b-customize-immediate`, based on `origin/main` at
`8b1b1c3` (Nitro and charged jump included).

Scope: B-owned Customize screen, category border styles, current-build stats
presentation, and the B-owned Test Drive footer entry. Clicking an available
part, paint, or vehicle choice changes the in-memory draft immediately and
records normal undo history; Save Build persists the edited draft. The
separate Equip action and Choices/Details tabs are removed. One Show Stats
button swaps the model for current-build values. Undo, Redo, Repair, and Manage
Saves sit in the footer; Test Drive matches Save Build height and sits directly
to its left, leaving Save Build rightmost. The header carries only the screen
title, category accent borders have square ends, and horizontal preview drag
follows the pointer.

Integration: the active Atlas MX B task is isolated at `codex/b-modular-chassis`
and has one overlapping Customize script change to resolve during rebase. This
task does not edit PlayerProfile, catalogue identity, gameplay, networking, or
the hosted service. A's general menu entry remains unchanged.

Validation: native visual inspection at 1920 × 1080 and 150% text scale;
headless Customize text, immediate choice/current stats, history, recovery,
pagination, and Test Drive entry checks; pinned Godot 4.7.2 baseline.
