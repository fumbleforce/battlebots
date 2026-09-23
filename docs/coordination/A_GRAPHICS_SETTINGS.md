# Graphics and settings overhaul — A, issue #29

Owner: A / Codex / x3d, session `a-graphics-settings-x3d-20260923`, branch
`codex/a-graphics-settings-overhaul` from `62d83f1`.

The user wants smooth, refined rendering and a substantial settings overhaul.
The old video panel exposed only mode/resolution/V-Sync despite project MSAA 4×.
MSAA misses specular/shader shimmer. Add working, persisted rendering controls
and quality presets; modernize the category hub and A-owned pages. Keep existing
B camera/input transactions intact through their published panels. B #28 owns
garage/customize and currently reserves HANDOFF; use this scoped record.

Design plan: steel blue ink #101b26, surface #172634, divider #314957, warm white
#e6e9df, amber #eebd65 and cool cyan #7dc5d4. Existing Barlow Condensed titles and
Barlow body/value text retain the game's identity. Replace oversized card grids
with a calm category list and actual arena art; detailed pages use aligned
label/description/value rows, Display/Quality/Effects tabs, a scrollable body
and stationary transaction footer. The distinguishing element is a real Foundry
view paired with clear machine-tuning controls. Avoid extra dashboard decoration.
At 150% text size, content scrolls while actions remain available.

Runtime plan: one client-local graphics owner updates current and newly added
viewports, world environments and authored shadow lights. Duplicate environment
resources and retain authored values so toggling quality never compounds color
adjustments or enables shadows on every fixture. Headless servers skip rendering.
Preferences live in version 2 video.cfg, migrating v1 display values with new High
defaults. Display rollback includes monitor, window position/mode and V-Sync;
quality rollback restores prior graphics. Apply quality-only changes immediately;
preview potentially disruptive display changes for 15 seconds. Save by temporary
file and rename so a failed write does not overwrite the previous settings.

Shared integration: project.godot rendering defaults only; no input actions,
BotCommand/BotView, camera behavior, catalogue or protocol changes. The general
menu owns GraphicsRuntime and supplies the settings transaction adapter. B panels
receive local theme styling only; no B source paths are modified.

Capability basis: actual Godot 4.7.2 ClassDB API checked locally; official
[anti-aliasing](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html)
and [resolution scaling](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html)
documentation informs AA/FSR choices. FSR2 handles its own temporal AA and runs on supported NVIDIA as well as AMD GPUs.
The settings explicitly say this after the user asked about NVIDIA options.
DLSS/DLAA are not exposed by the pinned renderer API and need a separate integration. MSAA-only
options remain for players preferring crisp non-temporal rendering. Native
render scale >100% supersamples; FSR methods cap at 100%. Forward+ effects are
disabled in the UI when unavailable. No pretend DLSS/ray-tracing/motion-blur
switches: those require integrations beyond the built-in pipeline.

## Implemented behavior and validation

High defaults use temporal AA + 2× MSAA, 16× anisotropic filtering, high shadows
and ambient occlusion, medium indirect lighting/reflections, authored bloom/fog,
debanding and specular smoothing. Ultra uses FSR2 at native resolution, higher
screen-space quality and 8192 shadow atlases. Low/Medium lower costs. Players can
select FXAA, SMAA, MSAA2/4/8, TAA or combined TAA/MSAA, FSR1/2, 50–150% native
render scale (FSR caps at 100%), sharpening, particle detail, brightness,
contrast, saturation, frame cap and counter. Monitor selection supplements the
existing modes, window resolution and V-Sync. Every option maps to a runtime API;
unsupported Forward+ controls are unavailable in other renderers.

Live material response stays authored: bloom/fog only enable where authored;
shadow Off restores only the original shadow casters when switched back on.
Particle quality scales allocation without overwriting dynamic emission density
or hiding damage cues. Node removal releases captured resources and weak
registrations, rather than retaining every previously loaded arena.

Passed with Godot 4.7.2:

- Native import, baseline, graphics preference migration/validation/persistence,
  quality-only Apply, save-error/cancel restoration and display timeout tests.
- Native runtime assertions for every AA mode, FSR2 exclusivity/render-scale
  clamp, effects, shadows, grading, frame limiter, particle budgets, new
  viewports/environments and scene-resource cleanup. Headless behavior is inert.
- Audio/accessibility transactions and text preview/cancel/save/reload; full
  menu-to-category and pause-to-category focus/input routing remains intact.
- Graphics page layout and every option's scroll reachability at 1280/1920/2560
  widths and 100%/150% text; stationary Apply/Keep/Revert/Cancel remain visible.
  Hub coverage includes 3840 width. Native screenshots reviewed after reducing
  row padding and moving AA to the top of image clarity.
- Actual X11 display operations on this three-monitor workstation: fullscreen
  and exclusive-fullscreen requests, timed rollback, window size, V-Sync,
  confirmed persistence, moving the real window to another monitor and Cancel
  restoring its original monitor. This is Linux evidence; Windows/Wayland and
  human preference/comfort review remain under #8.

Native evidence: [hub](evidence/graphics-settings-2026-09-23/hub.png),
[quality](evidence/graphics-settings-2026-09-23/quality.png),
[effects](evidence/graphics-settings-2026-09-23/effects.png),
[audio](evidence/graphics-settings-2026-09-23/audio.png),
[accessibility](evidence/graphics-settings-2026-09-23/accessibility.png),
[former MSAA4 image](evidence/graphics-settings-2026-09-23/msaa4-before.png),
[new High image](evidence/graphics-settings-2026-09-23/high.png),
[Ultra during camera motion](evidence/graphics-settings-2026-09-23/ultra-motion.png).

The native 1600×900 RTX 3080 fixture uses actual Foundry/Atlas with a static bot
and moving camera. GPU p95: Low 3.413 ms, High 5.700 ms, Ultra 7.169 ms. High wall-frame
p95 was 5.831 ms. This is bounded rendering evidence, not whole-game/low-end or
multiplayer certification. See [full samples](evidence/graphics-settings-2026-09-23/performance.json).
The pre-existing seven Texture RID shutdown warning remains tracked in #18.

Reproduction (Linux, no PowerShell):

```sh
godot --headless --path battlebots --script res://tests/presentation/graphics_preferences_test.gd
godot --headless --path battlebots --script res://tests/presentation/graphics_runtime_test.gd
godot --path battlebots --script res://tests/presentation/graphics_runtime_test.gd
godot --path battlebots --max-fps 60 --script res://tests/presentation/video_display_native_test.gd
godot --path battlebots --max-fps 60 --script res://tests/presentation/video_settings_layout_test.gd
godot --path battlebots --script res://tools/capture_settings_review.gd
godot --path battlebots --script res://tools/capture_graphics_review.gd
```

The user's subsequent driving dust/exhaust idea is deferred to [#31](https://github.com/fumbleforce/battlebots/issues/31)
at their explicit request. No lunar emitter/fog shader or B exhaust source edits
are included. Existing effects are consumed only through general quality controls.

Matching release evidence will follow artifact preparation and acceptance.
