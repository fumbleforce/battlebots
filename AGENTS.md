# Project Battlebots — repository instructions

Read docs/GAME_SPEC.md, docs/TEAM_WORKFLOW.md, docs/CONTRACTS.md and docs/HANDOFF.md before implementation. The game root is battlebots/, not the repository root.

## Two-person ownership
- Ask which role this session owns only if the task does not establish it; continue read-only inspection while clarifying.
- Developer A owns simulation, networking, weapons, services, core contracts, bot assembly, app bootstrap, project.godot, and data.
- Developer B owns arena, camera/input presentation, UI, art/audio, practice, and mock presentation fixtures.
- scenes/dev/a_simulation.tscn belongs to A; scenes/dev/b_presentation.tscn belongs to B.
- scripts/app_main.gd belongs to A. tests/fixtures/mock_bot.* belongs to B.
- Shared contracts require a documented handoff. Do not change another owner's paths incidentally.
- Use a separate local clone per computer and a separate codex/a-* or codex/b-* branch per task.
- Never assume another ChatGPT session shares memory or that its unmerged work is present.
- After each completed incremental iteration, commit only the task's changes,
  fetch origin, rebase the task branch onto origin/main, and push the task branch.
  Preserve unrelated working edits. Resolve and validate any rebase conflicts
  before pushing. If rebasing a previously pushed task branch rewrites its history,
  use --force-with-lease, never a blind force push or a force push to main.

## Baseline and validation
- Pin Godot to 4.7.2 stable. Preserve Jolt, 60 Hz physics, meter scale, Y up, and -Z forward.
- Keep authoritative logic free of camera/UI dependencies. Mocks are development-only.
- This is scaffolding, not implemented combat/networking. Do not describe placeholder behavior as a finished feature.
- Commit source .uid and required .import metadata; never commit .godot/, credentials, or export output.
- Run tools/check-baseline.ps1 with the local Godot executable after changing shared contracts/scenes.
- Before handoff, inspect Git diff/status, document validation and outstanding work, and avoid unrelated edits.
