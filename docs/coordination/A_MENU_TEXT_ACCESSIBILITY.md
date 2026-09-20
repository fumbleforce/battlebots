# A — General-menu text accessibility

Intent 2026-09-20, `codex/a-menu-text-accessibility`, base `35ef6a6`.
A reserves general menu composition, online/lobby/main/mode/arena/loading
presentation, results/reconnect/game menu, audio/HUD settings and independent
presentation checks. Carry the existing 100/125/150% text preference into these
menus with original-theme layouts that remain usable at 1280x720 and 1920x1080.
Preserve focus, live preview, cancellation, persistence and reconnect behavior.

Shared local helper: `MenuTextScale.apply(root, factor)` scales text from saved
base sizes without accumulating on repeat calls; each A screen/panel exposes
`apply_text_scale(factor)` to adapt its own layout. The menu-game owner applies
the current draft to new screens and restores saved values on Cancel.
No wire changes, B garage/customisation/control-settings implementation or input
bindings changes. B may consume the published helper in its own menu work;
whole-menu acceptance remains open until those owned surfaces are covered.

Independent work owns disjoint general navigation screens and match-flow panels;
the parent owns helper, settings, composed-game integration and documentation.
Validate enlarged text bounds/navigation in detached screens and the complete
game, plus saved/default/cancel behavior and existing 1v1 menu regressions.

## Implemented behavior

The existing `HudPreferences.text_scale` also drives A's general menus; version
one files stay compatible. Accessibility settings name this scope explicitly,
preview their own enlarged controls and preserve Save/Cancel semantics. The
sample keeps its intended scale instead of multiplying twice. Settings overlays
scroll with keyboard focus when content exceeds the viewport.

Main navigation, online entry, host/join/connected lobby, mode/arena selection
and loading retain the original theme. Larger text wraps; dense bodies scroll,
and newly rebuilt arena hazards/roster labels retain the chosen size. Game-menu
actions follow keyboard focus, results keep overview/score actions and readable
round history, and score columns wrap within the available width. Reconnect
keeps retry/leave accessible while its explanatory body can scroll.

`menu_text_settings_test`, `menu_text_screens_test` and `match_menu_text_test`
are registered in the presentation gate. Detached checks cover 720p/1080p/4K,
100/125/150% and restoration, dynamic content, focus/scroll reachability and
font sizes. Composed-game checks cover live drafts, cancellation, saved reload
and opening another screen with the saved size. Native D3D12 captures at720/1080
were inspected for settings and match-flow panels; native general-screen
captures were also inspected. Visual review corrected wrapping and overlap
missed by initial coarse bounds checks.

Local captures: Godot user data `a-menu-text-settings-*.png` and
`menu-text-*.png`; temporary directory `battlebots-match-text-*-*.png` for
match-flow screens. Captures are local validation artifacts, not source assets.

B follow-up: use the noncompounding `MenuTextScale.apply` helper inside owned
garage/customisation/control-settings layouts, adapt wrapping/scrolling and
validate them independently before claiming whole-menu coverage. No changes to
B scripts or input bindings were made here. Human low-vision/color-vision
acceptance, world markers, pings and the Windows shutdown defect remain open.

## Validation and integration

Godot 4.7.2 stable/Jolt: baseline import/smoke and the full presentation runner
passed, including its real HTTP/ENet lobby, online, reconnect, results/rematch
and service checks. After final review, A's two entry buttons inside Settings
also scale; their bounds at720p and the composed settings test pass. The latest
general-screen fixture, HUD integration and actual-session reconnect test were
rerun after those final edits and pass. Reconnect now explicitly asserts that
cancelling an unsaved large-text draft restores the recovery panel's saved size.

The full runner reported two-to-four ObjectDB instances at exit in some fixtures,
but no native crash in this run. This is scoped menu evidence and does not close
the intermittent Windows failure or certify all CI. No gate was weakened.
Commit, fetch/rebase preserving merges, and integrate this completed increment
into main; B's owned text-layout work and the other board items remain open.
