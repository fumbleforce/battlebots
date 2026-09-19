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

Implemented and tested. GameplayInputGate handles suspension and release-to-rearm;
the existing preview is still the only local input producer. A's lifecycle gate
remains intact and no authoritative files were edited.

Independent scene: res://scenes/dev/b_input_menu.tscn (F6). The fixture uses
CombatState with Controller stats: hold LMB to charge; deliberate release launches;
Escape or focus loss cancels. No drive/network simulation is claimed by this scene.

Evidence: baseline smoke; input_menu_test headless and rendered; existing camera
and settings tests; A's duel_menu_smoke and navigation_smoke all pass. The rendered
1280x720 menu was inspected. Tests dispatch GUI actions for Tab/Enter/Escape and
verify that a pending settings resume cannot defeat a subsequent focus loss.

Keyboard/mouse rebinding is explicitly B-04b, still open. Human two-computer feel
acceptance remains open. A's coordination log in DEVELOPER_B_TODO.md is preserved.

## B-04b next increment — independent look axes

B will add separate horizontal/vertical sensitivity to the existing settings modal,
with live preview, cancel/reset and version-2 persistence. Version-1 files migrate
in memory by applying the old shared sensitivity to both axes; only Save rewrites
files. The legacy sensitivity property remains as a setter for both axes so existing
A/B consumers keep their behavior. No action map, app, wire or command changes.
Acceptance: distinct orbit deltas, inversion, legacy migration, invalid-value fallback,
save/reload/cancel/defaults, keyboard order and rendered 1280x720 layout.
This is one B-04b increment; binding capture and weapon toggle remain pending.

Independent look axes implemented: both sliders apply live, persist separately,
and restore on Cancel/defaults. Legacy version-1 loads do not rewrite disk; Save
writes version 2. Untouched custom axis precision survives unrelated UI edits.
The existing b_presentation scene and camera_settings_test exercise migration,
orbit/inversion, persistence, keyboard focus and modal suppression. Rendered
1280x720 panel fits without clipping. No A-owned runtime files changed.
Validation: baseline PASS; all three presentation suites PASS; A duel/menu smoke PASS; rendered settings test PASS. Independent read-only subagent review completed; its precision finding is fixed and regression-tested.

## B-04b rebinding and weapon mode — implementation intent

B now implements a separate local input-preferences file and a Controls page within
the existing settings modal. Keyboard/mouse mappings replace only those runtime
InputMap events while the preview is alive; controller events and UI actions remain
intact, and the prior map is restored on exit. No project.godot or wire changes.
Capture rejects duplicate/reserved controls and wheel bindings for held actions.
Save activates validated bindings; Cancel discards the draft. Escape cancels capture
first. Settings remain visible throughout, preserving A's existing modal/input gate.

Toggle primary is opt-in: first press activates, second press deliberately releases
(and fires a charged lifter); secondary/menu/focus suppression cancels and clears
its latch. Keep SessionBotSource.input_allowed for lifecycle suppression. Independent
model, real-CombatState toggle, and GUI binding tests will cover this increment.
Parallel subagents own the preference model and toggle gate/tests; B owns modal
integration, rendered inspection, combined checks and handoff. Same focused branch.

## B-04b result and A integration handoff

Rebinding and hold/toggle primary implemented. The Controls page remains inside
settings_panel.visible, with draft edits, conflict/reserved-key validation, explicit
Save & back and Cancel & back, plus nested Escape cancellation. Existing public
preview APIs remain. Runtime mapping changes restore on exit and preserve controller
bindings. The new b_controls scene has separate fixture preferences.

B now also reads SessionBotSource.input_allowed before sampling to clear toggle
intent during countdown/elimination; A's source guard remains. No A-owned runtime
files, commands or protocol changed. A should update its hardcoded build_hint to
use preview.input_preferences labels and toggle_primary when refreshing its menu.

Evidence: baseline and all six presentation suites PASS. These cover model
validation/persistence, real-lifter toggle/cancellation, raw keyboard and mouse GUI
capture, nested Escape, save failure, restart persistence, physical held-key
rearming, lifecycle suppression and prior-map restoration. A duel/menu and navigation
smokes PASS. Both camera and Controls panels rendered at 1280x720 and inspected.
Two subagents implemented independent model/gate work and reviewed integration;
the GUI fixture's script-retention warning was fixed with a separate lifecycle probe.
Controller remapping, 150% text scaling, human LAN feel and later B features remain.
