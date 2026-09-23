# Project Battlebots — repository instructions

The Godot project root is `battlebots/`. Read docs/GAME_SPEC.md,
docs/TEAM_WORKFLOW.md and docs/CONTRACTS.md before implementation.

## Collaboration (GitHub issues)
- Before starting or resuming work (and after context compaction), read the
  [coordination board #2](https://github.com/fumbleforce/battlebots/issues/2), the
  active issues and your own issue. Run `node tools/check-collaboration.mjs`
  (add `--issue <n>` once you have one) to verify `gh` access and see current work.
- Every task needs an issue; search for an existing one first. Post a short CLAIM
  describing the functionality you are building so no one else builds the same
  or an overlapping feature. Claims are not file locks: anyone may edit any file.
  When your work touches code another active task is changing, say so on that
  issue and integrate carefully.
- Post progress, blockers, contract changes and completion on the issue (and
  cross-task news on #2). Details: [docs/ISSUE_WORKFLOW.md](docs/ISSUE_WORKFLOW.md).
- Always close an issue as soon as its work is done (integrated to `main`, green
  deploy), with a closing comment naming the commits. Do not leave finished
  cards open.
- Reopen the issue if the user pushes back on the implementation, and continue
  the work there.
- A follow-up request that does not overlap with the original issue gets a new
  issue; link it from the original.
- There are no fixed roles; any session may work on any area.

## Branches and integration
- One clone or worktree per session, one branch per task. Never assume another
  session shares memory or that its unmerged work is present.
- After each finished increment: commit only the task's changes, rebase onto
  `origin/main`, run the relevant checks, merge into `main` and push `main`.
  No pull requests. A pushed feature branch alone is not done.
- Preserve unrelated working edits. Use `--force-with-lease` only on your own
  rewritten task branch; never force-push `main`.
- Shared contracts (BotCommand/BotView/loadouts, WireCodec, prediction-to-drive
  boundary, project.godot input actions) change with producer and consumer
  updated together and a docs/CONTRACTS.md entry.

## Releases
- Client and hosted server are one release. Gameplay, catalogue or wire changes
  bump `WireCodec.BUILD` (and `PROTOCOL` for wire changes) so stale peers are
  rejected instead of desynchronising. Never bypass or disguise that rejection.
- Pushing to `main` deploys the hosted server automatically (Linux hosted duel
  runtime workflow; see services/matchmaking/DEPLOYMENT.md). Online play is ready
  only when that run is green and live `/healthz` matches the local build.

## Engineering rules
- Godot 4.7.2 stable, Jolt, 60 Hz physics, meters, Y up, −Z forward.
- Tuning values live in named config (`battlebots/data/*.json` read through a
  typed loader, e.g. `data/bot_physics.json` / `BotPhysics`), never as bare
  numbers in logic or tests.
- Keep authoritative logic free of camera/UI dependencies; mocks are
  development-only.
- Before bot modelling, material, baking or asset-export work, read
  docs/art/STYLIZED_INDUSTRIAL_ASSETS.md.
- Before weapon, effects, weapon-sound or recoil work, read
  docs/art/WEAPON_FEEL.md (how the turret weapons were made to look, sound
  and feel good, plus a checklist for new parts).
- Before arena or environment work, read docs/art/ARENA_ENVIRONMENTS.md (how
  the Woodland arena was built, failures to avoid, and a checklist for new arenas).
- Before performance or load-time work, read docs/PERFORMANCE.md (how to
  measure, what worked, warnings and open ideas).
- New `class_name` scripts are unknown to checkouts launched with a stale
  editor class cache (#65, #74). Runtime code must `preload` them (a static
  factory loads its own script by path), list them in
  `tools/check-stale-class-cache.py` (run by `tools/check-mvp.ps1`), and that check must pass before pushing
  `main`: `python3 tools/check-stale-class-cache.py --godot <godot>` after an
  editor import.
- Commit source `.uid` and required `.import` files; never commit `.godot/`,
  credentials or export output.
- Running the game from source re-imports changed assets automatically
  (`ImportGuard`, docs/coordination/IMPORT_GUARD.md); headless tests still need
  the explicit `--editor --import` step after a pull.
- After shared contract/scene changes run `tools/check-baseline.ps1` (needs
  PowerShell) or the equivalent Godot test scripts it lists.
- This is a developing MVP: do not describe unverified behaviour or partial scope
  as finished. Before handing off, review the diff and record validation and
  outstanding work on the issue.
