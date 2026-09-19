# Project Battlebots

Godot **4.7.2 stable** / Jolt / typed GDScript. Two developers, one repository, separate local clones.

## Start
1. Clone the repository locally and install Godot 4.7.2 stable.
2. Import `battlebots/project.godot` into Godot.
3. Press **F6** on your sandbox or **F5** for the development launcher.
4. Choose Developer A (physical driving sandbox) or Developer B (animated mock state).

The baseline contains a 50 × 50 floor, team spawn markers, registered input actions,
and typed input/view adapters. A's sandbox now supports WASD driving and Space braking,
with temporary test walls and an overview camera. The yellow stripe marks the front.
B's sandbox retains its animated mock and static preview. Combat, recovery,
camera orbit, a finished arena, and networking are **not** implemented.

## Work independently
- **A:** `battlebots/scenes/dev/a_simulation.tscn` — drive controller, then networking.
- **B:** `battlebots/scenes/dev/b_presentation.tscn` — implement arena/camera/UI using the mock.
- Read [handoff](docs/HANDOFF.md), [contracts](docs/CONTRACTS.md),
  [team workflow](docs/TEAM_WORKFLOW.md), and [full specification](docs/GAME_SPEC.md).
- Agree who is A/B, then branch from the common baseline:
  `git switch -c codex/a-drive-controller` or `git switch -c codex/b-arena-camera`.
  These are examples; branches are not created by the baseline.

## Verify
From the repository root in PowerShell:

```powershell
./tools/check-baseline.ps1 -GodotPath "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"
```

The check imports resources, loads both sandboxes, checks contracts/input bindings,
and verifies the physical body settles on the floor. It needs no export templates.
Run `./tools/check-drive.ps1 -GodotPath "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"`
for the baseline checks plus headless Jolt driving, braking, contact, and input-failure checks.
For manual inspection, use F5 and both launcher buttons; Escape returns to the launcher.
Public hosting and export presets are deliberately left for A after the first network spike.
