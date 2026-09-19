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
B's sandbox retains its animated mock in this branch. The separate A MVP console
adds combat, recovery and networking; see the MVP section below. B's finished
arena, orbit camera and UI are being delivered on B's branch.

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
Public hosting is a later release task; MVP export presets are described below.

## Developer A MVP (codex/a-mvp)

The launcher now includes **Developer A — MVP practice / network console**.
This temporary console exercises the session API; B owns the finished menus,
camera, HUD and garage. WASD/Space drive/brake, LMB powers the spinner or raises
the lifter (release fully charged to flip), RMB brakes/lowers, and R self-rights
when eligible. Select Striker/Controller, then Practice/reset to test either build.

Use Godot 4.7.2 from the repository root (replace `$GodotPath` with your executable):

```powershell
& $GodotPath --headless --path battlebots -- --server --port=24567
& $GodotPath --path battlebots -- --join=127.0.0.1 --port=24567 --ready
& $GodotPath --path battlebots -- --host --port=24567
& $GodotPath --path battlebots -- --practice --controller
./tools/check-mvp.ps1 -GodotPath $GodotPath
./tools/check-processes.ps1 -GodotPath $GodotPath
```

A dedicated server requires four clients; a listen host requires three joining
clients. Ready all four slots. For LAN use the host's LAN address in place of
127.0.0.1. The console exposes host/join/ready/rematch/forfeit/leave; reconnect is
available through the session API using the in-memory token.

Exports: `Windows Client` and `Linux Server` in `battlebots/export_presets.cfg`.
Install matching templates, create `battlebots/exports/windows` and `exports/linux`,
then run `--headless --path battlebots --export-release "Windows Client"` (or
`"Linux Server"`). The dedicated-server feature automatically selects headless
server startup. The GitHub workflow pins engine/templates, checks official hashes,
runs the suite and exports both artifacts. Generated binaries stay ignored.

Read [CONTRACTS.md](docs/CONTRACTS.md) for B's API and [A_MVP_TASKS.md](docs/A_MVP_TASKS.md)
for implemented scope and remaining joint acceptance. Full 5v5/FFA, the other
weapon families, public identity/allocation and release polish are post-MVP phases.
