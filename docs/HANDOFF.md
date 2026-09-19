# Baseline handoff

## Available now
- Runnable F5 development launcher.
- A-owned passive rigid-body bot and simulation sandbox.
- B-owned mock bot and presentation sandbox; works without drive/network code.
- Shared BotCommand, BotView, BotSource and BaselineConfig.
- InputMap, 60 Hz physics, collision layer names, project directories and smoke check.
- B-owned basic floor, team spawn markers, static camera and diagnostic label.

No driving, combat, online connection, game-mode logic, loadout builder, or finished
camera is implemented. The current scene composition is for development, not a
production session architecture. Both fixtures intentionally share the baseline
arena/preview; preserve their public node/API boundary while evolving those scenes.

## Developer A starts here
Branch example: codex/a-drive-controller.
Open scenes/dev/a_simulation.tscn (F6).
Implement drive forces in scripts/simulation and consume the existing BotCommand.
Keep BotSource/read_view/camera_anchor stable for B.
Next implement a headless authoritative session and two-client input/snapshot test.
Own app wiring, data, bot assembly and engine configuration. Request arena or visual
changes from B instead of editing B's evolving scene.

Acceptance for first task: W/S and A/D drive the physical bot; braking works;
the body settles, turns and survives wall contacts; state is available through
BotView; no UI dependencies enter simulation code.

## Developer B starts here
Branch example: codex/b-arena-camera.
Open scenes/dev/b_presentation.tscn (F6).
Use tests/fixtures/mock_bot.tscn until A's drive is merged.
Build collision-aware mouse camera against BotSource.camera_anchor/exclusions.
Complete the arena perimeter and FFA markers; retain the 50-meter interior.
Replace the diagnostic label with reusable UI as needed. Keep mock state explicit.

Acceptance for first task: mouse orbit, recenter, zoom and horizon stabilization
work against the mock; camera respects walls; team/FFA markers follow the spec.
Do not change simulation or project.godot; send missing action/settings requests to A.

## First joint integration
Merge small PRs into the shared baseline, then run A's real body with B's camera.
Verify on both office computers. Continue to networking before expanding content.
Use docs/TEAM_WORKFLOW.md for LAN checks, ownership and session handoff format.

## Next ChatGPT session

Baseline validation: Godot 4.7.2.stable.official.ed1daf0bf imported the project
successfully; the headless smoke check loaded the launcher and both sandboxes,
verified input bindings and snapshot isolation, and confirmed the rigid body
settles on the floor. Visual interaction and LAN multiplayer are not validated
by this check; multiplayer is not implemented yet.

State your role explicitly: "I am Developer A" or "I am Developer B", then identify
one task and its acceptance criteria. Ask the session to read AGENTS.md and these
docs first. Each developer has a separate local clone and task branch.
