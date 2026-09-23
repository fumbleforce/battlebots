# Shared issue workflow

GitHub Issues are the live task tracker for **every human, machine and agent
harness with repository access**. The pinned [coordination board #2](https://github.com/fumbleforce/battlebots/issues/2)
is the common communication channel. This applies equally to Codex, Claude,
Cursor, other harnesses and manual development. A/B describe feature ownership,
not which application someone uses. Historical TODO/handoff entries do not reserve
paths; the latest explicit issue claim does.

## Local startup and access

Each checkout needs Git, the project's existing Node 24 environment and GitHub CLI
(`gh`). Use the existing nvm installation on Linux; do not install a separate Node
distribution or introduce PowerShell. If `gh` is missing, install the official
CLI for that operating system from <https://cli.github.com>, then authenticate
**on that machine**:

```sh
gh auth login
gh auth status
node tools/check-collaboration.mjs
node tools/check-collaboration.mjs --issue 123
```

Replace 123 with the actual task. The read-only script verifies GitHub access and
repository write permission, prints the current branch/commit, all open task
statuses, the board and recent comments, active/blocked reservations and the
selected issue. It fails if access is unavailable or the selected issue is closed.
Read full linked histories when context requires it. A passing check does not
claim work, resolve overlap or establish acceptance of another machine.

Run this check at every session start/resume and after context compaction. Consult
the tracker again before changing scope/paths and before integration. If GitHub is
unavailable, report it and continue read-only/local investigation; do not establish
new edit reservations from a stale local snapshot. Never copy credentials between
machines, print tokens, or put credentials in issue comments. Existing valid local
authentication is enough; do not make users log in repeatedly.

Append a machine/harness attestation to [setup issue #26](https://github.com/fumbleforce/battlebots/issues/26)
when a new setup first passes: UTC time, machine/checkout, harness, GitHub login
and preflight result. A shared login does not identify distinct sessions. Known
collaborators are `fumbleforce` and `JosteinE`; each verifies their active setups.
Other machines are unverified until they report. New machines follow this rule
even after the current inventory is accepted.

## Find, claim and coordinate work

1. Read #2, all active/blocked reservations and relevant task comments. Search
   open **and closed** issues before making a new task. Use a new issue for new
   work; reopen an existing issue only for a genuine regression or unmet scope,
   explaining why. Break large work into separately claimable tasks.
2. State scope, acceptance, dependencies and A/B ownership in the issue. Do not
   turn a design idea into implementation without an agreed scope. Templates
   support feature/investigation work, bugs and ideas.
3. Post a claim on the task and a short linked announcement on #2. Assign your
   GitHub login and set `status:active`. Name a unique session, including harness
   and machine; two agents using `fumbleforce` are still separate claimants.
4. **Re-read the task, board and overlapping active tasks after posting.** GitHub
   comments are not an atomic lock. If simultaneous claims overlap, the earliest
   uncontested claim takes precedence; agree a split/transfer in comments before
   either edits the overlap. Keep useful independent work moving. Do not infer
   permission from a stale timestamp or old branch name.
5. Shared contracts need the documented handoff already required by AGENTS. Link
   the affected issues and wait for conflicting owners to agree before editing
   their reserved paths. Expand your claim before touching new areas. Preserve
   unrelated working changes and maintain separate task branches/checkouts.

Example task comment (fill in actual values):

```text
CLAIM — 2026-09-23T11:00:00Z
Role: A | GitHub: fumbleforce | Harness: Codex
Session: a-menus-x3d-20260923-1100 | Machine/checkout: x3d /home/.../battlebots
Branch/base: codex/a-example / <commit>
Reserved: exact files or clearly bounded area
Shared interfaces/dependencies: issue links; agreed handoff or none
Plan/checks: intended behavior and relevant validation
Next update: 2026-09-23T11:30:00Z
```

Use structured `gh` arguments and `--body-file` for multiline comments. This avoids
shell interpolation of backticks, dollar signs and literal newlines.

```sh
gh issue view 123 --comments
gh issue comment 123 --body-file /path/to/claim.md
gh issue edit 123 --add-assignee @me --add-label status:active --remove-label status:backlog
gh issue comment 2 --body-file /path/to/linked-announcement.md
```

Remove whichever old status label actually exists. Do not assign an absent agent
or reserve their paths on their behalf. Role labels mark responsibility; a claim
comment marks current ownership of a task and its paths.

## Status and communication

The pinned board links live GitHub filtered views. Labels update the board
immediately, so concurrent agents do not rewrite a shared status table. Each open
task has exactly one status label; the permanent board has none.

| Label | Meaning |
| --- | --- |
| `status:backlog` | Available and unclaimed |
| `status:active` | Named session is implementing or validating a defined scope |
| `status:blocked` | Explicit dependency prevents progress; state what unblocks it and which paths remain reserved |
| `status:verification` | Implementation exists but specified acceptance/setup remains; activate and claim before editing |
| `status:deferred` | Outside current priority; do not silently start it |

Use `owner:A`/`owner:B`, `area:*`, `priority:1v1`, `bug`, and `kind:idea` to route
work. Larger modes, ten-player optimization and tutorials remain deferred until
the user's 1v1 priority is satisfied. Closing an issue is the completed state;
remove its `status:*` label so searches do not imply a current reservation.

Post progress at meaningful checkpoints and at least every **30 minutes** while
actively working: what changed, what was learned, checks/evidence, blockers,
remaining work, current paths and next update time. Recheck other reservations
before expanding scope. Posts on #2 are for cross-task claims, blockers,
dependencies, handoffs, completion and useful ideas; keep implementation detail
on the task. Mention affected people only when their input is needed.

Use append-only comments for progress instead of modifying another agent's body
or comment. Before pausing/ending, post `HANDOFF` with current commit/branch,
checks, outstanding work and explicit path release/retention. Release an
unattended task to backlog, or mark a real dependency blocked; do not leave it
silently active. A handover requires the receiving session's acknowledgement.
Old claims do not automatically expire into permission to edit.

Ideas belong in `kind:idea` issues, announced on #2 when useful across owners.
Describe evidence, tradeoffs and affected contracts. Discussion is welcome;
accepted ideas become scoped implementation issues. Durable decisions, reasoning,
contracts and reusable lessons go in docs with links in both directions.

## Integration and closure

Follow AGENTS: check/commit the scoped increment, fetch/rebase (preserving merges
where required), resolve conflicts, validate, merge locally to main and push main.
No PRs. Consult current reservations again before integration. Gameplay/catalogue/
network changes also require matching tested clients/server, live compatibility
and the required external acceptance; a merged source branch alone is not done.

Before closing a task, post `DONE` with the main commit, behavior delivered,
validation/evidence, deployment identity when relevant, released paths and links
to any separately scoped remaining acceptance. Do not move required acceptance
to a new issue just to declare incomplete work finished. Close with the correct
reason and announce completion on #2. Keep human playtesting and other-machine
setup open until verified. The pinned coordination board remains open by design.

## Migrated backlog

[ISSUE_INDEX.md](ISSUE_INDEX.md) maps the previous A/B TODOs to task issues. It is
an index and historical migration record, not a second live status board. Old
handoffs retain evidence; use current issues for ownership and progress.
