# Standard gamepad input (#22)

The gameplay preview now accepts a standard mapped gamepad alongside keyboard
and mouse. Bindings are fixed in this first increment; keyboard/mouse rebinding
continues to preserve controller events. The Controls modal has a Controller
page, and the preview hints follow the last input device.

| Input | Action |
| --- | --- |
| Left stick | Analog drive and steering |
| Right stick | Orbit / turret aim / mortar ground target |
| RT / LT | Primary / secondary; turret / hull weapon on turret builds |
| LB / RB | Brake / Nitro |
| A (south) | Hold to charge jump; release to jump |
| X (west) | Recovery |
| Left / right stick press | Walker crouch / camera recenter |
| D-pad up / down | Camera zoom |
| View / Back | Hold scoreboard |
| Start | Pause menu |
| D-pad, A, B | Menu navigation, confirm, back |

`project.godot` maps any controller device onto the existing input actions, with
0.2 deadzones. Explicit `ui_accept` and `ui_cancel` definitions retain their
keyboard bindings and add A/B: the pinned project's inherited definitions did
not include controller confirm/cancel. No BotCommand, simulation, wire,
catalogue or compatibility version changes.

`GamepadInput` converts the radial-deadzone right-stick vector to orbit pixels
per second, then uses the existing camera sensitivity/inversion and sight pitch
limits. `data/controller_input.json` sets 800 pixels/s and caps a single frame's
integration at 0.1 s. Mortar camera geometry, launch targeting and per-weapon
hints remain owned by their existing presentation code.

Menus, focus changes and settings changes require held gameplay actions and the
look stick to return to neutral before they can resume. Physical controller
polling preserves held-action suppression when keyboard rebinding clears the
InputMap action state. Disconnecting a controller used by the preview releases
controls immediately, brakes and cancels charged weapons/jump; reconnecting
alone does not resume. Mouse activity can change hints without forgetting which
controllers need disconnect handling.

## Validation

Pinned Godot 4.7.2, Linux. `gamepad_input_test.gd` injects process-local Godot
joypad events through the real InputMap and menu dispatch. It covers analog
strength/deadzones, reverse commands, each gameplay binding, real lifter charge
and cancellation, GUI Resume, held-stick/trigger suppression, remapping,
focus/disconnect/reconnect, camera inversion and equal integrated orbit at
30/120 FPS, plus keyboard-capture cancellation from B. A real Atlas mortar
checks artillery camera retention, moving ground target/valid aim and RT/LT
turret/hull commands. This is synthetic integration, not hardware acceptance.

The same synthetic gameplay check also passes in a native window; it waits
for initial window-manager focus before testing the production focus gate.

Baseline, existing input-menu/preferences/settings, camera-settings, Atlas
turret and Scorpion input checks pass after rebasing onto the new weapon,
walker and practice-respawn work. Final integration also preserves #64 local
part shortcuts, its keyboard defaults/migration and the Local dev settings
page; baseline, input and native layout checks pass on that combined tree. The settings layout matrix covers 720p/4K
at 100/125/150% text and restoration to 100%; each controller label must fit.
Native Forward+ on RTX 3080 verifies the same layout and retained capture:
[Controller guide at 720p/150%](evidence/controller-input/controller-guide-150.png).

Reproduce:

```sh
godot --headless --path battlebots --script res://tests/presentation/gamepad_input_test.gd
godot --path battlebots res://tests/presentation/control_settings_text_test.tscn -- --capture
```

For the capture, set `TEMP` to an existing output directory. The focused input
check is registered in the presentation runner. Human physical-controller,
driving/camera/spectator feel and controller rebinding remain open on #22.
The normal coordinated workflow produces clients containing this presentation
increment; its existing compatible server needs no new protocol or gameplay.

## Direct launch after pulling the controller change (#65)

The first controller integration relied on the editor-generated global script
class cache for `GamepadInput`. A checkout imported before #22 could therefore
fail immediately when launched after pulling it, before another editor import.
The first error was `Identifier GamepadInput not declared`; failed preview and
settings initialization then left `menu_game.gd:658` calling `observe_match` on
Nil. The earlier tests all ran after import and missed this launch state.

Both runtime consumers now explicitly preload the controller helper. The new
`tools/check-gamepad-startup.ps1`, run by the baseline gate, temporarily removes
only GamepadInput's cache entry, runs the actual menu/host/garage/Practice flow
without an editor rescan, rejects script errors even if Godot exits zero, and
restores the exact original cache bytes in `finally`. Run sequentially with
imports. This reproduced the reported parse/observe_match failure before the
fix and passes afterward. Native default-main launch with the same stale cache
also passes. Controller behavior and compatibility versions are unchanged.

The broader validation run separately found the existing 150 ms network-contact
CI failure (#13) and a Practice fixture bounds assertion comparing a hidden HUD
in logical canvas coordinates with physical window dimensions. Those are not
proof of a passing full suite and are separate from this startup regression.
