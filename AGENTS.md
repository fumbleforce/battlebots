# Project Battlebots — repository instructions

Read docs/GAME_SPEC.md, docs/TEAM_WORKFLOW.md, docs/CONTRACTS.md and docs/HANDOFF.md before implementation. The game root is battlebots/, not the repository root.

## Two-person ownership
- Ask which role this session owns only if the task does not establish it; continue read-only inspection while clarifying.
- Current user-defined split: A owns menus, networking, game rules, game world and audio. B owns combat, bot assets (models/weapons), bot-customisation menus and player controls. This supersedes historical ownership in older handoffs.
- A owns general menu/lobby/loading/results flows, sessions/services, match lifecycle/scoring, arena/world/environment, audio and app/export integration.
- B owns combat/damage/resources/recovery mechanics, weapon behavior/presentation, bot assembly/catalogue, garage/customisation, driving/input/camera controls and their settings.
- Existing folders mix responsibilities: simulation/match_state.gd and authority_world.gd are A; combat_state.gd, drive_body.gd, drive_model.gd, mvp_bot.gd and weapons/ are B. Menu shell/router are A; bot garage/customisation screens and their profile/loadout persistence are B.
- Shared command/view/loadout contracts, prediction-to-drive boundaries, project.godot/input actions, and mixed dev scenes require a documented handoff. Follow feature ownership rather than historical folder or author names; see docs/TEAM_WORKFLOW.md.
- Shared contracts require a documented handoff. Do not change another owner's paths incidentally.
- Use a separate local clone per computer and a separate codex/a-* or codex/b-* branch per task.
- Never assume another ChatGPT session shares memory or that its unmerged work is present.
- After each completed incremental iteration, commit only the task's changes,
  fetch origin and rebase the task branch onto origin/main. When finished,
  merge it locally into main and push main directly. Do not create pull requests.
  Use --rebase-merges when the task depends on the published A/B integration
  merge; do not flatten and replay both teams' already-resolved historical edits.
  Preserve unrelated working edits. Resolve and validate any rebase conflicts
  before pushing. If rebasing a previously pushed task branch rewrites its history,
  use --force-with-lease, never a blind force push or a force push to main.
- When a task branch is complete, merge it locally into the shared main branch after its required checks and conflict validation, then push main directly. No PRs. Pushing a finished feature branch alone is not completion: do not leave the latest game scattered across unmerged branches.
- After merging, fetch and base the next task on updated origin/main. Integrate completed dependency branches as part of the merge; leave genuinely in-progress work separate and identify it in the handoff. Never force-push main. If a required check or branch protection blocks a merge, state the concrete blocker rather than claim the branch is finished.

## Baseline and validation
- Pin Godot to 4.7.2 stable. Preserve Jolt, 60 Hz physics, meter scale, Y up, and -Z forward.
- Keep authoritative logic free of camera/UI dependencies. Mocks are development-only.
- This is a developing MVP with implemented combat/networking and remaining
  placeholders. Check the current acceptance trackers; do not describe unverified
  behavior or partial MVP scope as a finished full game.
- Commit source .uid and required .import metadata; never commit .godot/, credentials, or export output.
- Run tools/check-baseline.ps1 with the local Godot executable after changing shared contracts/scenes.
- Before handoff, inspect Git diff/status, document validation and outstanding work, and avoid unrelated edits.
