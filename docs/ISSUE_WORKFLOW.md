# Shared issue workflow

GitHub Issues are the live task tracker for **every human, machine and agent
harness with repository access**. The pinned [coordination board #2](https://github.com/fumbleforce/battlebots/issues/2)
is the common communication channel. This applies equally to Codex, Claude,
Cursor, other harnesses and manual development. There are no fixed roles; the
former A/B ownership labels are retired. A claim says what functionality a
session is building so others do not build the same or overlapping features; it
is not a file lock, and anyone may edit any file.

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
statuses, the board and recent comments, active/blocked claims and the
selected issue. It fails if access is unavailable or the selected issue is closed.
Read full linked histories when context requires it. A passing check does not
claim work, resolve overlap or establish acceptance of another machine.

Run this check at every session start/resume and after context compaction. Consult
the tracker again before changing scope and before integration. If GitHub is
unavailable, report it and continue local work; do not claim new functionality
from a stale local snapshot. Never copy credentials between
machines, print tokens, or put credentials in issue comments. Existing valid local
authentication is enough; do not make users log in repeatedly.

Append a machine/harness attestation to [setup issue #26](https://github.com/fumbleforce/battlebots/issues/26)
when a new setup first passes: UTC time, machine/checkout, harness, GitHub login
and preflight result. A shared login does not identify distinct sessions. Known
collaborators are `fumbleforce` and `JosteinE`; each verifies their active setups.
Other machines are unverified until they report. New machines follow this rule
even after the current inventory is accepted.

## Find, claim and coordinate work

1. Read #2, all active/blocked claims and relevant task comments. Search
   open **and closed** issues before making a new task. Use a new issue for new
   work; reopen an existing issue only for a genuine regression or unmet scope,
   explaining why. Break large work into separately claimable tasks.
2. State scope, acceptance, dependencies and affected areas in the issue. Do not
   turn a design idea into implementation without an agreed scope. Templates
   support feature/investigation work, bugs and ideas.
3. Post a claim on the task and a short linked announcement on #2. Assign your
   GitHub login and set `status:active`. Name a unique session, including harness
   and machine; two agents using `fumbleforce` are still separate claimants.
4. **Re-read the task, board and overlapping active tasks after posting.** If
   two claims cover the same or overlapping functionality, agree in comments who
   builds what before either continues; the earliest claim takes precedence.
   Editing files another task also touches is fine: mention it on that issue and
   integrate carefully (rebase, keep both behaviours).
5. Shared contracts need the documented contract change already required by
   AGENTS; link the affected issues. Update your claim if your scope grows.
   Preserve unrelated working changes and keep separate task branches/checkouts.

Example task comment (fill in actual values):

```text
CLAIM — 2026-09-23T11:00:00Z
GitHub: fumbleforce | Harness: Codex
Session: menus-x3d-20260923-1100 | Machine/checkout: x3d /home/.../battlebots
Branch/base: codex/example / <commit>
Scope: the functionality being built (main areas/files touched, for context)
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
or claim work on their behalf. A claim comment marks who is building a task.

## Status and communication

The pinned board links live GitHub filtered views. Labels update the board
immediately, so concurrent agents do not rewrite a shared status table. Each open
task has exactly one status label; the permanent board has none.

| Label | Meaning |
| --- | --- |
| `status:backlog` | Available and unclaimed |
| `status:active` | Named session is implementing or validating a defined scope |
| `status:blocked` | Explicit dependency prevents progress; state what unblocks it |
| `status:verification` | Implementation exists but specified acceptance/setup remains; activate and claim before editing |
| `status:deferred` | Outside current priority; do not silently start it |

Use `area:*`, `priority:1v1`, `bug`, and `kind:idea` to route
work. Larger modes, ten-player optimization and tutorials remain deferred until
the user's 1v1 priority is satisfied. Closing an issue is the completed state;
remove its `status:*` label so searches do not imply the work is still claimed.

Post progress at meaningful checkpoints and at least every **30 minutes** while
actively working: what changed, what was learned, checks/evidence, blockers,
remaining work and next update time. Recheck other claims before expanding
scope. Posts on #2 are for cross-task claims, blockers,
dependencies, handoffs, completion and useful ideas; keep implementation detail
on the task. Mention affected people only when their input is needed.

Use append-only comments for progress instead of modifying another agent's body
or comment. Before pausing/ending, post `HANDOFF` with current commit/branch,
checks and outstanding work. Release an
unattended task to backlog, or mark a real dependency blocked; do not leave it
silently active. A handover requires the receiving session's acknowledgement.
A stale claim is not a reason to rebuild the same feature; ask on the issue first.

Ideas belong in `kind:idea` issues, announced on #2 when useful across owners.
Describe evidence, tradeoffs and affected contracts. Discussion is welcome;
accepted ideas become scoped implementation issues. Durable decisions, reasoning,
contracts and reusable lessons go in docs with links in both directions.

## Integration and closure

Follow AGENTS: check/commit the scoped increment, fetch/rebase (preserving merges
where required), resolve conflicts, validate, merge locally to main and push main.
No PRs. Check the board for overlapping work again before integration. Gameplay/catalogue/
network changes also require matching tested clients/server, live compatibility
and the required external acceptance; a merged source branch alone is not done.

Before closing a task, post `DONE` with the main commit, behavior delivered,
validation/evidence, deployment identity when relevant and links
to any separately scoped remaining acceptance. Do not move required acceptance
to a new issue just to declare incomplete work finished. Close with the correct
reason and announce completion on #2. Keep human playtesting and other-machine
setup open until verified. The pinned coordination board remains open by design.

## Migrated backlog

[ISSUE_INDEX.md](ISSUE_INDEX.md) maps the previous A/B TODOs to task issues. It is
an index and historical migration record, not a second live status board. Old
handoffs retain evidence; use current issues for ownership and progress.
