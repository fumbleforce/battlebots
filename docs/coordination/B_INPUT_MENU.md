# B-04 — input and menu coordination

Owner: B. Branch: codex/b-input-menu.
Dependency base: origin/codex/a-b-integration at bdb42ef.
The sawblade-tank art branch is intentionally separate and is not a dependency.

## Intent published before implementation

B will implement A's requested cancellation behavior in the presentation adapter:
all menu/focus-suppressed commands will brake and lower/cancel the weapon.
Holding a gameplay control through a menu will not reactivate it on resume until
that control has been released. This includes drive, weapons and recovery.

The standalone preview will gain explicit keyboard-accessible Resume, Camera
settings and Return buttons. Escape will open/close the menu rather than destroy
the current scene. Explicit Return will consume input before a deferred transition.
A's live session menu retains ownership of navigation and match/session actions.

## Boundaries for A

B edits scripts/presentation, scripts/ui, scenes/ui, a new B-owned independent
test scene/fixture, tests/presentation and B-owned docs. No edits to scenes/app,
simulation, networking, core contracts, project.godot or integration tests.
Keep SessionBotSource's input_allowed gate: it still owns lifecycle/authority
suppression even after B correctly cancels menu/focus suppression.

No wire protocol or BotCommand field changes are planned. Preserve the existing
preview API: controls_enabled, capture_controls, release_controls, open_settings,
settings_panel, rig and hud. A can keep hiding the preview CanvasLayer while its
own menu is visible.

## Planned evidence

- Standalone interactive b_input_menu scene with real charged-lifter rules.
- Cancellation cannot turn into an attack; intentional release still launches.
- Held drive/weapon/recovery input requires release before reactivation.
- Keyboard focus/navigation and explicit deferred return preserve scene lifetime.
- Existing B settings/camera tests and A's live-duel menu regression remain green.
- Rendered menu inspection at 1280 x 720.

## Rebinding boundary

Complete input rebinding is a later B-04b increment, now that A has confirmed
camera settings can remain locally owned. B-04a does not silently remap keys or
change InputMap. It establishes the input suppression boundary first.

## Status

Intention published; implementation in progress. A's coordination section in
DEVELOPER_B_TODO.md is preserved. Human two-computer feel acceptance remains open.
