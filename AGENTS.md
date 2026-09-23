# Project Battlebots — repository instructions

Read docs/GAME_SPEC.md, docs/TEAM_WORKFLOW.md, docs/CONTRACTS.md and docs/HANDOFF.md before implementation. The game root is battlebots/, not the repository root.

## Mandatory GitHub collaboration — every developer and harness
- **ALWAYS consult the GitHub issue tracker before starting or resuming work.** Read the pinned [coordination board #2](https://github.com/fumbleforce/battlebots/issues/2), active/blocked tasks and your issue including recent comments. Repeat after context compaction, before expanding into new paths and before integration. Local TODOs and old handoffs are historical evidence, not live reservations.
- Run `node tools/check-collaboration.mjs --issue <number>` at session start (omit `--issue` while finding work). This verifies local `gh` authentication, repository write access and shows current claims. Every machine/harness with repository access must pass; authenticate locally with `gh auth login` if needed. Never share or log tokens. Record new machine/harness verification in [setup issue #26](https://github.com/fumbleforce/battlebots/issues/26).
- Every new feature, bugfix, investigation or documentation task needs a GitHub issue; search for an existing one first. Update the issue for existing work. Before editing, post a `CLAIM` with harness, machine/checkout, unique session ID, branch/base commit, exact reserved paths/areas, shared contracts, intended checks and UTC next-update time. Set `status:active`, assign your GitHub account and announce the linked claim on #2. Shared accounts are not agent identities.
- Re-read the task and board after claiming. Resolve overlapping reservations through issue comments before touching shared paths; comments are coordination, not an atomic lock. Keep independent work moving. Never take ownership merely because a claim is old; explicitly agree and record transfers.
- Keep task progress current at meaningful milestones and at least every 30 minutes while active. Post cross-task blockers, contract proposals, handoffs, completion and ideas on #2 with task links. Use append-only comments instead of rewriting another agent's status. Maintain one `status:*` label per open task; identify paused/released paths and the next action before ending a session.
- Close feature/bugfix issues only after their required checks, integration to `main` and matching hosted release when applicable. Post commits, evidence and remaining acceptance links first; release path reservations and notify #2. Keep unverified human/machine acceptance open. The permanent board stays open.
- Follow [docs/ISSUE_WORKFLOW.md](docs/ISSUE_WORKFLOW.md) for status meanings, claim/update formats, local setup and conflict handling. Share proposals in issues; put permanent decisions, contracts and learnings in docs and link them back to the issue.

## Shared ownership
- There are no fixed roles. Any session may work on any area (menus, networking,
  rules, world, audio, combat, bots, garage, controls, releases). The historical
  A/B split in older docs, handoffs and issue comments is retired; treat it as
  history, not as ownership.
- Coordinate through the GitHub issues instead: claims name the exact paths a
  session is editing, and overlapping reservations are resolved in issue comments.
  Do not change paths another active claim reserves incidentally; ask on its issue.
- Shared command/view/loadout contracts, prediction-to-drive boundaries,
  project.godot/input actions and mixed dev scenes still need their contract
  change documented in docs/CONTRACTS.md and announced on #2.
- Use a separate local clone or worktree per session and a separate `codex/*`
  (or harness-named) branch per task.
- Never assume another session shares memory or that its unmerged work is present.
- After each completed incremental iteration, commit only the task's changes,
  fetch origin and rebase the task branch onto origin/main. When finished,
  merge it locally into main and push main directly. Do not create pull requests.
  Preserve unrelated working edits. Resolve and validate any rebase conflicts
  before pushing. If rebasing a previously pushed task branch rewrites its history,
  use --force-with-lease, never a blind force push or a force push to main.
- When a task branch is complete, merge it locally into the shared main branch after its required checks and conflict validation, then push main directly. No PRs. Pushing a finished feature branch alone is not completion: do not leave the latest game scattered across unmerged branches.
- After merging, fetch and base the next task on updated origin/main. Integrate completed dependency branches as part of the merge; leave genuinely in-progress work separate and identify it in the handoff. Never force-push main. If a required check or branch protection blocks a merge, state the concrete blocker rather than claim the branch is finished.

## Coordinated client and hosted-server releases
- Treat the client and hosted server as one release: build both from the same
  tested commit. Catalogue, gameplay, networking or compatibility changes must
  bump `WireCodec.BUILD` (and PROTOCOL for wire changes) so stale peers are
  rejected instead of desynchronising.
- Hosted server deploys are automated: every push to `main` touching the game,
  service or release tooling runs the **Linux hosted duel runtime** workflow,
  which prepares the release from that commit, passes the local production
  container duel, then runs `tools/deploy-hosted.mjs` (wait for a playtest break,
  `fly deploy`, verify live `/healthz` matches the commit's manifest, external
  private/Quick Play duel, automatic rollback on failure). After pushing a
  server-affecting change, check that run; a failed or still-waiting deploy means
  hosted play is not ready. See services/matchmaking/DEPLOYMENT.md.
- On requests to get or launch the latest game, compare the local build ID,
  protocol and generated catalogue hash with the configured service's `/healthz`
  before presenting online play as ready. Report mismatches or an unreachable
  service immediately; a successful local launch does not verify Quick Play.
- Keep compatibility rejection intact. Never bypass it or update only the health
  manifest to disguise stale game workers. Errors must remain visible and explain
  the version mismatch; identify whether the client or server needs updating when
  release evidence establishes which is stale.
- The deploy waits for `/healthz` to report no occupied rooms before restarting
  the single Machine (a restart ends running matches) and keeps the previous
  image for rollback. Manual deploys use the same script with `FLY_API_TOKEN`.
  Verify the live service with tools/check-hosted.mjs --endpoint <configured
  HTTPS origin> --duel-only --godot <pinned Godot executable>.

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
