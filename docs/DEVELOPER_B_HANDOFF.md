# Developer B — arena and third-person camera

Owner: Developer B. Branch: `codex/b-arena-camera`. Base: `60feafe`.

This implements B's first foundation task. It supersedes the baseline notes about
missing walls and a static camera; shared core contracts remain unchanged.

## Delivered

- A 50 × 50-meter floor, three-meter perimeter walls, two-meter corner chamfers,
  symmetric team markings and eighteen spawn markers. Geometry is serialized in
  the arena scene and loads headlessly without visual scripts.
- Team1_1..5 and Team2_1..5 retain their existing names/transforms; use slots 2 and
  4 for 2v2. FFA_1..8 are evenly distributed at radius 20, facing the center.
- A reusable BotOrbitCamera consuming only BotSource. Mouse orbit, 4–9m zoom,
  middle-click recenter, optional gentle auto-recenter after 1.5 seconds of idle
  mouse input while driving, and horizon stabilization independent of bot roll.
- A 0.25m sphere sweep against World/Bots, excluding the source's own RIDs. The
  boom shortens immediately and extends smoothly. Floor/perimeter/chamfer limits
  keep the camera inside even when looking down over the physical walls.
- A diagnostic HUD, cursor capture/release, neutral commands on focus loss, and
  suppression of weapon activation from the click that recaptures the cursor.
- Mock-only WASD movement, a visible front bumper, wheels, and test shortcuts.
  This is presentation testing, not drive physics or collision simulation.

## Run and controls

Open `battlebots/scenes/dev/b_presentation.tscn` and press F6, or select B in F5's
launcher. Click inside the arena if the cursor is released.

| Control | Result |
|---|---|
| Mouse / wheel / MMB | Orbit / zoom / recenter |
| WASD / Space | Move the mock / brake |
| 1 / 2 / 3 | Place mock at center / south wall / southeast corner |
| 4 | Toggle upside-down mock |
| 5 | Toggle automatic recentering |
| Escape | Release cursor; press again to return to launcher |

Sensitivity, inversion, recenter speed and automatic recenter are exported on the
OrbitCamera node. First-person view, settings persistence/remapping, obstruction
outlines, combat effects and a finished HUD are later tasks.

## Integration for A

The existing A sandbox already instances the same preview and therefore uses the
new camera without editing any A-owned scene. Preserve BotSource's camera_anchor,
camera_exclusions and detached read_view methods. Include every owned physics
RID in camera_exclusions; this prevents clipping behavior when a bot is inverted.

The camera assumes this single arena is centered at the origin, axis-aligned,
with half extent 25 and chamfer 2. For other layouts, configure these exports or
introduce an agreed arena manifest. No new InputMap actions or engine settings
are required. Physics stays at 60 Hz and Jolt remains the backend.

Review wall/chamfer colliders with real drive physics before merging. The floor
has no new collision seams, hazards or gameplay modifiers. The mock intentionally
clamps its visual movement inside the perimeter and never simulates contacts.

## Validation

Run the existing `tools/check-baseline.ps1` with Godot 4.7.2, followed by:

```powershell
& $GodotPath --headless --path battlebots --script res://tests/presentation/camera_arena_test.gd
```

The presentation test checks physical input bindings, all FFA headings/radii,
perimeter and chamfer collision, camera clearance across wall/corner/pitch/yaw
cases, an interior obstruction, zoom/pitch limits, manual/automatic recenter,
horizon stability, neutral input, target deletion, and the A bot's own-collider
exclusion. A rendered D3D12/Forward+ run can save a preview with `-- --capture`.

Godot 4.7.2 import and baseline smoke checks passed. The camera/arena test passed
headlessly and in a rendered run; the saved preview was visually inspected.
Actual human input feel and real drive/network interaction still need joint
playtesting. No multiplayer functionality is claimed by this task.

## Repository state

An existing local `battlebots/project.godot` edit was present before B started.
It was preserved and is excluded from B's commit. No simulation, networking,
bot assembly, shared contracts, data, or application-bootstrap files were edited.
Merge this branch through normal review; do not replace A's evolving scenes.
