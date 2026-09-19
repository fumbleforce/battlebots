# Project Battlebots

Godot **4.7.2 stable** / Jolt / typed GDScript. Two developers, one repository, separate local clones.

## Start
1. Clone the repository locally and install Godot 4.7.2 stable.
2. Import `battlebots/project.godot` into Godot.
3. Press **F6** on your sandbox or **F5** for the development launcher.
4. Choose Developer A (passive physics body) or Developer B (animated mock state).

The baseline contains a 50 × 50 floor, team spawn markers, a static preview camera,
a status label, registered input actions, and typed input/view adapters. It does
**not** implement driving, combat, camera orbit, a complete walled arena, or networking.
WASD is collected as input but intentionally does not move the passive body yet.

## Work independently
- **A:** `battlebots/scenes/dev/a_simulation.tscn` — implement movement and then networking.
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
and verifies the passive body settles on the floor. It needs no export templates.
For manual inspection, use F5 and both launcher buttons; Escape returns to the launcher.
Public hosting and export presets are deliberately left for A after the first network spike.
