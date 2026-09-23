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
  cross-task news on #2). Close issues after integration to `main` and a green
  deploy. Details: [docs/ISSUE_WORKFLOW.md](docs/ISSUE_WORKFLOW.md).
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
- Commit source `.uid` and required `.import` files; never commit `.godot/`,
  credentials or export output.
- After shared contract/scene changes run `tools/check-baseline.ps1` (needs
  PowerShell) or the equivalent Godot test scripts it lists.
- This is a developing MVP: do not describe unverified behaviour or partial scope
  as finished. Before handing off, review the diff and record validation and
  outstanding work on the issue.
