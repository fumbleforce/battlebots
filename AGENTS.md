# Project Battlebots — repository instructions

Read docs/GAME_SPEC.md, docs/TEAM_WORKFLOW.md, docs/CONTRACTS.md and docs/HANDOFF.md before implementation. The game root is battlebots/, not the repository root.

## Mandatory GitHub collaboration — every developer and harness
- **ALWAYS consult the GitHub issue tracker before starting or resuming work.** Read the pinned [coordination board #2](https://github.com/fumbleforce/battlebots/issues/2), active/blocked tasks and your issue including recent comments. Repeat after context compaction, before expanding into new paths and before integration. Local TODOs and old handoffs are historical evidence, not live reservations.
- Run `node tools/check-collaboration.mjs --issue <number>` at session start (omit `--issue` while finding work). This verifies local `gh` authentication, repository write access and shows current claims. Every machine/harness with repository access must pass; authenticate locally with `gh auth login` if needed. Never share or log tokens. Record new machine/harness verification in [setup issue #26](https://github.com/fumbleforce/battlebots/issues/26).
- Every new feature, bugfix, investigation or documentation task needs a GitHub issue; search for an existing one first. Update the issue for existing work. Before editing, post a `CLAIM` with role, harness, machine/checkout, unique session ID, branch/base commit, exact reserved paths/areas, shared contracts, intended checks and UTC next-update time. Set `status:active`, assign your GitHub account and announce the linked claim on #2. Shared accounts are not agent identities.
- Re-read the task and board after claiming. Resolve overlapping reservations through issue comments before touching shared paths; comments are coordination, not an atomic lock. Keep independent work moving. Never take ownership merely because a claim is old; explicitly agree and record transfers.
- Keep task progress current at meaningful milestones and at least every 30 minutes while active. Post cross-task blockers, contract proposals, handoffs, completion and ideas on #2 with task links. Use append-only comments instead of rewriting another agent's status. Maintain one `status:*` label per open task; identify paused/released paths and the next action before ending a session.
- Close feature/bugfix issues only after their required checks, integration to `main` and matching hosted release when applicable. Post commits, evidence and remaining acceptance links first; release path reservations and notify #2. Keep unverified human/machine acceptance open. The permanent board stays open.
- Follow [docs/ISSUE_WORKFLOW.md](docs/ISSUE_WORKFLOW.md) for status meanings, claim/update formats, local setup and conflict handling. Share proposals in issues; put permanent decisions, contracts and learnings in docs and link them back to the issue.

## Two-person ownership
- Ask which role this session owns only if the task does not establish it; continue read-only inspection while clarifying.
- Current user-defined split: A owns menus, networking, game rules, game world and audio. B owns combat, bot assets (models/weapons), bot-customisation menus and player controls. This supersedes historical ownership in older handoffs.
- A owns general menu/lobby/loading/results flows, sessions/services, match lifecycle/scoring, arena/world/environment, audio and app/export integration.
- B owns combat/damage/resources/recovery mechanics, weapon behavior/presentation, bot assembly/catalogue, garage/customisation, driving/input/camera controls and their settings.
- The user explicitly reiterated that A is not responsible for controls. A must not take on driving, camera, braking, weapon-control or self-righting exercises as tutorial work. Hand those to B; A may integrate the menu entry and consume published interfaces.
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

## Coordinated client and hosted-server releases
- Treat the client and hosted server as one release: build both from the same
  tested commit. Catalogue, gameplay, networking or compatibility changes must
  include a matching server release before declaring hosted play ready. B must
  hand server-affecting changes to A explicitly; merging them alone does not
  establish that the live service is updated.
- Use one release workflow: run required checks, prepare matching client/server
  artifacts, deploy the server, compare live compatibility information, and run
  the external private/Quick Play duel check through results and rematch before
  marking the client release ready. Record commit, image and verification evidence
  in the handoff. Until this workflow is automated, perform these steps explicitly;
  passing build CI alone is not proof of a matching live deployment.
- On requests to get or launch the latest game, compare the local build ID,
  protocol and generated catalogue hash with the configured service's `/healthz`
  before presenting online play as ready. Report mismatches or an unreachable
  service immediately; a successful local launch does not verify Quick Play.
- Keep compatibility rejection intact. Never bypass it or update only the health
  manifest to disguise stale game workers. Errors must remain visible and explain
  the version mismatch; identify whether the client or server needs updating when
  release evidence establishes which is stale.
- Deploy updates to the existing single-Machine service during a playtest break:
  restarting it ends active matches. Until match draining exists, establish that
  the break is in effect before restarting. Retain the previous release for
  rollback, and report failed deployment/acceptance as an incomplete release.
- See services/matchmaking/DEPLOYMENT.md and tools/prepare-hosted.ps1. Verify the
  live service with tools/check-hosted.mjs --endpoint <configured HTTPS origin>
  --duel-only --godot <pinned Godot executable>.

## Baseline and validation
- Before bot modeling, material, baking or asset-export work, read
  docs/art/STYLIZED_INDUSTRIAL_ASSETS.md and its linked accepted native references.
  It records the Atlas fidelity techniques, failed approaches and required visual/
  technical checks. Apply the construction principles; do not impose Atlas's exact
  dimensions, colors or track layout on every model.
- Pin Godot to 4.7.2 stable. Preserve Jolt, 60 Hz physics, meter scale, Y up, and -Z forward.
- Keep authoritative logic free of camera/UI dependencies. Mocks are development-only.
- This is a developing MVP with implemented combat/networking and remaining
  placeholders. Check the current acceptance trackers; do not describe unverified
  behavior or partial MVP scope as a finished full game.
- Commit source .uid and required .import metadata; never commit .godot/, credentials, or export output.
- Run tools/check-baseline.ps1 with the local Godot executable after changing shared contracts/scenes.
- Before handoff, inspect Git diff/status, document validation and outstanding work, and avoid unrelated edits.
