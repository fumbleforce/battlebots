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
