# Main menu composition and practice setup — 20 September 2026

Owner A, branch `codex/a-main-menu-cleanup`, base `ac2bda4`. User requests less
text, consistent alignment and action placement in the main-menu bot card, and
arena selection within Practice. A owns main-menu composition and practice
routing. Delegated B component work is limited to an opt-in compact presentation
API in FeaturedVehicle/GarageBotPreview and its direct checks; default workshop
and lobby presentation and input behavior remain owned by B.

Reserved paths: main_menu.gd/.tscn, menu_router.gd, arena_select.gd/.tscn,
featured_vehicle.gd, garage_bot_preview.gd, affected presentation fixtures and
this handoff. The existing project.godot and model import working edits are
unrelated and must be preserved outside this task's commit.

Acceptance: one clear vehicle identity with aligned switching/customization
actions, prominent real rotating preview, accessible pause and invalid-build
feedback; no arena selector on main; Practice chooses an arena before starting.
Verify 720p, 1080p, wide and 4:3 layouts at 100–150% text, existing selection and
workshop/lobby behavior, practice/back flow, and baseline. No gameplay,
catalogue or transport change or hosted deployment is planned.

## Delivered behavior and validation

Main now uses concise play/navigation actions, a separate Settings/Quit footer,
and an 820px logical-width card with consistent padding. The preview expands
above a single vehicle-name/count/arrow row; pause/resume is an icon with a
tooltip and accessible name. Redundant selection/instruction captions are gone.
Full-name tooltips and ellipsis keep long names inside their own column.

Practice opens arena setup and starts only after Start Practice. Back cancels
selection without saving or creating a session; direct workshop Test Drive
remains direct. Leaving setup clears its intent so later LAN/generic navigation
cannot accidentally start Practice. Enlarged text reduces the repeated detail
image height to keep the entire Practice setup visible without scrolling.

Godot `4.7.2.stable.official.ed1daf0bf` validation:

- Baseline passes in both the shared checkout and a clean isolated worktree.
- MAIN MENU FIT, MENU HOST FIT, MENU KIT, FEATURED VEHICLE MENU and PRACTICE MENU
  pass; existing selection/host authority and practice lifecycle remain intact.
- FEATURED VEHICLE, GARAGE SHOWCASE and GARAGE PREVIEW pass with compact/default
  toggling, noncompounding text sizes, before-ready configuration and long names.
- ARENA SELECTION passes with real Main → Practice and Practice → LAN → generic
  navigation, plus explicit no-scroll bounds at 720p/1080p and 100/150% text.
- Native D3D12 main captures pass 720p, 1080p, ultrawide and 5:4 at 100–150%.
  Main and Practice screenshots were visually reviewed. An independent keyboard
  probe confirms Enter selection/pause/resume, Tab escape, invalid-build recovery
  and disabled empty-inventory behavior.

Reproduce captures with `main_menu_fit_test.gd -- --capture` and
`arena_selection_test.gd -- --capture` under tests/presentation. Images go to
`user://main-fit-*.png` and `user://practice-setup-*.png`. Human visual acceptance
remains with the user. This client presentation change does not certify or deploy
a hosted release.
