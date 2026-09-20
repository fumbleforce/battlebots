# B menu text accessibility

Intent to A: `codex/b-menu-text-accessibility` starts from main `d6e154e`.
Consume the published MenuTextScale helper and existing HUD text preference in
B's Garage, Customize, catalogue, recovery and input/camera settings. Preserve
100/125/150% fonts without compounding and reflow/scroll at 1280x720 through 4K.

Ownership: primary owns Customize, preview/comparisons/recovery and integration;
subagent owns Garage/catalogue; another owns camera/input settings. Separate
independent scenes test dynamic rows, focus, bounds and saved-setting propagation.
One coordinated A-owned integration edit in menu_game.gd will pass the existing
text factor to preview.settings_panel using apply_text_scale. No settings schema,
input actions, session or wire changes. No other A implementation is reserved.

Validate largest text, restoration to 100%, fresh/rebuilt rows, invalid builds,
recovery review, input capture, camera values and composed settings propagation.
Run baseline and affected regressions, update outdated docs/comments, then merge
the completed branch into main and push directly.

Completed: B panels implement apply_text_scale, dynamic rows use the current
factor, comparison headings stay whole, and wrapping/focus-following scrolls
preserve full-sized text. Garage actions sit outside the viewport and its body
scrolls independently of footer actions. Catalogue tabs use a separate strip.
Customize retains visible budgets and Save with scrollable choices/details;
preview validation and file-recovery review remain readable at 150%.

Camera/input controls retain draft/preview/capture/save/cancel semantics. The
stable camera Form path now sits in a ScrollContainer; general injected buttons
are included in Tab navigation. Window resizing re-reveals the focused control
after layout. The one documented menu_game call propagates the live shared
setting. No other A runtime edits or preference/schema changes.

Godot 4.7.2 validation: BASELINE, CUSTOMIZE TEXT, GARAGE CATALOGUE TEXT,
CONTROL SETTINGS TEXT and B MENU TEXT GAME pass. The four new independent scenes
are registered in check-presentation.ps1. Rendered 150% Customize, invalid draft,
backup review, Garage and catalogue/control screens were inspected at 720p;
layout/font checks cover 100/125/150/revert through 4K. Composed tests cover live
preview, Cancel, explicit persistence, fresh navigation and preserved input
suppression. Existing CAMERA SETTINGS, INPUT SETTINGS, MENU TEXT SETTINGS,
GARAGE PREVIEW, GARAGE COMPARISON PANEL, GARAGE REPAIR, GARAGE RECOVERY and
MENU CUSTOMIZATION SCREENS pass. git diff --check is clean.

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
