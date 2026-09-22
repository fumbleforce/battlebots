# B garage model thumbnails and save status — 22 September 2026

Owner: B. Branch: `codex/b-garage-model-thumbnails`, based on `main` at
`c3561b5`.

Scope: the Garage bot list, its row component, and a B-owned presentation
renderer. Each valid local loadout should receive a still image captured from
its actual equipped 3D model. Changed parts or cosmetics must refresh the
image; list rebuilds should reuse unchanged captures. Invalid drafts should
show no unrelated concept art. The footer places a quiet, backgroundless
Saved File link left of Done, while a visible status calls out unsaved edits,
new builds, retained copies, or saved-file errors. Main-menu, match, network,
and catalogue contracts remain unchanged.

Acceptance: rendered thumbnails for Sawblade and Scorpion are visibly distinct;
editing a loadout changes its thumbnail; returning to Garage reuses the current
appearance; the list remains responsive and the larger interactive preview
still works. Validate with pinned Godot 4.7.2 and capture a rendered garage
screen for inspection.

Implementation: one offscreen `GarageBotPreview` captures 256 × 160 stills into
`ImageTexture` resources. The in-memory cache is keyed by parts and cosmetics,
so names and list refreshes reuse the same capture. Changed weapon or paint
gets a new image. Invalid builds show no unrelated art; their repair status
remains visible in the row. No bot/gameplay data or catalogue identity changes.

The Garage derives save status from the existing profile baseline and save
indices. Clean builds have no status clutter; unsaved builds get an amber
footer message and row label. A file that needs review gets a red footer
message. Done still returns to the main menu; Save Build stays in Customize.
Both active B sessions on 22 September edit `player_profile.gd`, so this
increment deliberately does not change that shared file. The garage layout
work is isolated in its own worktree until integration.

Validation: Godot 4.7.2 baseline passes. The native D3D12 garage capture test
passes image-content checks for Sawblade vs. Scorpion, weapon edits, paint edits,
a reopened Garage, footer link placement/style, and unsaved/saved transitions.
Headless garage layout, pagination, Scorpion garage, and customization-screen
checks pass. Native screenshot was inspected at 1920 × 1080; all four starter
rows show their own model.
