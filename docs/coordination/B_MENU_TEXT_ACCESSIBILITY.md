# B menu text accessibility

Intent to A: `codex/b-menu-text-accessibility` starts from main `d6e154e`.
Consume the published MenuTextScale helper and existing HUD text preference in
B's Garage, Customize, catalogue, recovery and input/camera settings. Preserve
100/125/150% fonts without compounding at 1280x720 through 4K. Rebased onto A's
`fe9f2f0`; the newer no-scrolling feedback supersedes the initial scroll approach.

Ownership: primary owns Customize, preview/comparisons/recovery and integration;
subagent owns Garage/catalogue; another owns camera/input settings. Separate
independent scenes test dynamic rows, focus, bounds and saved-setting propagation.
The coordinated menu_game integration passes the existing text factor to
preview.settings_panel using apply_text_scale and lets its responsive layout
use actual window dimensions instead of shrinking A's former fixed-size frame.
No settings schema, input actions, session or wire changes.

Validate largest text, restoration to 100%, fresh/rebuilt rows, invalid builds,
recovery review, input capture, camera values and composed settings propagation.
Run baseline and affected regressions, update outdated docs/comments, then merge
the completed branch into main and push directly.

Completed: B panels implement apply_text_scale; dynamic rows use the current
factor and comparison headings stay whole. Garage shows two builds per page and
Loadout/Stats tabs; catalogue has two cards or rule panels per page. Customize
has two choices per page, a Details view and paged comparison stats while budgets
and Save stay visible. Preview validation reasons and recovery review text use
pages too. These panels contain no scrolling navigation and retain full fonts.

Camera/input controls retain draft/preview/capture/save/cancel semantics. Camera
labels sit beside the sliders in a responsive form; bindings use Driving, Weapons
and Camera & HUD groups. Their stable APIs integrate with A's new themed hub.
The camera Form and MarginContainer paths remain valid. Removed the stale
Scoreboard (planned) label now that A publishes the actual held scoreboard.

Godot 4.7.2 validation: BASELINE, CUSTOMIZE TEXT, GARAGE CATALOGUE TEXT,
CONTROL SETTINGS TEXT and B MENU TEXT GAME pass. The four new independent scenes
are registered in check-presentation.ps1. Rendered 150% Customize, invalid draft,
backup review, Garage and catalogue/control screens were inspected at 720p;
layout/font checks cover 100/125/150/revert through 4K. Composed tests cover live
preview, Cancel, explicit persistence, fresh navigation and preserved input
suppression. Existing CAMERA SETTINGS, INPUT SETTINGS, MENU TEXT SETTINGS,
GARAGE PREVIEW, GARAGE COMPARISON PANEL, GARAGE REPAIR, GARAGE RECOVERY,
SETTINGS HUB and MENU CUSTOMIZATION SCREENS pass after integration with fe9f2f0.
Composed native screenshots verify both themed Camera and Controls at 150% and 720p.
Tests now assert paging and no ScrollContainers instead of the superseded scroll
layout; recovery checks verify text across pages. git diff --check is clean.

A diagnostic observation: unthrottled composed runs intermittently reported two
MP3 objects (AudioStreamPlaybackMP3 and AudioStreamMP3) at exit. The new composed
fixture caps rendering at 60 fps so the real audio thread gets teardown time;
the final verbose run and existing general-settings test pass without warnings
at that cadence. This is not a claimed audio/runtime shutdown fix. No gameplay,
network or audio acceptance is inferred from the text fixtures.

Stale runtime text about fixed B settings/concept-only preview is removed.
Current contracts, handoffs and both boards reflect completed text support.
Authored bot-art integration, direct unsaved-build test-drive navigation and
full combat/control/human hosted-1v1 acceptance remain separate open work.

Final composed bounds also pass at 2560x1080 ultrawide and 1280x1024. Twelve-record recovery review pages retain every name and invalid entry at 150%, with no hidden overflow. The current A featured-vehicle/showcase request remains open for the next B increment.
