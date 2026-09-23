# Team workflow — Project Battlebots

## Live coordination across all harnesses

The user requires GitHub Issues for every new and updated task. **ALWAYS** read
the [pinned coordination board #2](https://github.com/fumbleforce/battlebots/issues/2),
active/blocked issues and your task/comments before starting/resuming work, after
compaction, before expanding scope and before integration. Run
`node tools/check-collaboration.mjs --issue <number>` on every developer machine
and harness. Claim the functionality you are building (unique session/harness/
machine identity, branch, next update) so no one builds the same or overlapping
features; claims are not file locks. Resolve overlapping functionality first.
Update at meaningful checkpoints and at least every 30 minutes while active.
Post handoffs, dependencies and ideas on #2; close tasks after tested integration
and required release. Permanent decisions/learnings still belong in docs.

See [the complete issue workflow](ISSUE_WORKFLOW.md),
[migrated task index](ISSUE_INDEX.md) and
[machine setup verification #26](https://github.com/fumbleforce/battlebots/issues/26).
Historical local TODO and handoff status is superseded by current issue claims.
There are no fixed roles: any session may take any area. The former A/B split
in older docs and handoffs is retired history.

## Areas and shared interfaces

Any session may work in any area and edit any file; issue claims say what
functionality is being built.
The game divides into these areas, and some folders mix several of them:

- Menus and HUD: main navigation, host/join, lobby, loading, match HUD, results,
  rematch, general settings (scripts/ui/, ui/menus/, presentation/menu_game.gd).
- Networking and services: scripts/networking/, services/matchmaking/, hosted
  release tooling and CI.
- Rules and world: simulation/match_state.gd, authority_world.gd, scenes/arenas/,
  scripts/arena/, spawns and world collision.
- Combat and bots: scripts/weapons/, simulation/combat_state.gd, drive_body.gd,
  drive_model.gd, mvp_bot.gd, scenes/bots/, bot models/materials, catalogue and
  validation, data/bot_physics.json.
- Garage and controls: garage/customisation screens and previews, PlayerProfile,
  LoadoutStore, input, camera and their control settings.
- Audio: assets/audio/ and scripts/audio/.

Shared interfaces (BotCommand, BotView, BotSource, loadout records, versioned
content identity, WireCodec) connect these areas. Change them only with producer
and consumer updates in the same integration and a docs/CONTRACTS.md entry.
Client prediction consumes the drive model: do not change physical drive
behavior incidentally to fix prediction, and never bypass server authority to fix
control or combat presentation. Changes to project.godot input actions and shared
scene wiring are announced on #2. Mixed dev scenes and fixtures keep their
historical a_/b_ filename prefixes; those prefixes carry no ownership.

## Coordination and branches

1. Read GAME_SPEC.md, CONTRACTS.md, HANDOFF.md and current shared task notes.
   The current user priority (2026-09-20) is a fully working 1v1 game, with external
   matchmaking/server deployment, HUD and general menu refinement prioritized.
   Multiplayer/networking screens must fit the original menu system. Human tunnel multiplayer
   succeeded per the user. Defer 2v2, other modes and tutorial work until 1v1 is
   fully working; existing implementations remain without creating active scope.
2. Use a separate local checkout or worktree and a `codex/*` (or harness-named)
   task branch. Do not change another session's checkout or assume sessions
   share memory.
3. Record intent, scope and acceptance in the task issue's CLAIM; longer design
   notes may go in docs/coordination/.
4. Scenes, resources and binary assets do not merge: before editing one another
   active task is also changing, agree the order on its issue. Text scripts merge;
   rebase carefully and keep both behaviours. Preserve unrelated local edits.
5. Commit each completed increment, fetch origin, rebase the task branch onto
   origin/main.
   Verify conflicts and any changed tree before integrating and pushing main.
   Use --force-with-lease only if an already-published task history was rewritten;
   never blind-force or force-push main.
6. When a branch is complete, merge it locally into shared main and push main
   directly after required checks and conflict validation. Do not create PRs.
   A pushed feature branch alone
   is not finished work. Keep main as the latest combined game rather than making
   other sessions locate a chain of unmerged task branches. Fetch the merged
   main and base the next task on it. Leave genuinely unfinished work separate;
   document any required-check or branch-protection blocker explicitly.
7. Update producer, consumer and isolated checks when changing shared contracts.
   Leave the exact API, behavior, source commit and evidence on the issue.

## Validation and handoff

Use pinned Godot 4.7.2 stable, Jolt, 60 Hz, meters, Y up and -Z forward. The Godot
root is battlebots/. Keep server logic independent of rendered UI. Mocks are
fixtures, never authoritative runtime implementations. Preserve source .uid and
required .import metadata; do not commit .godot/, credentials or export output.

Run the baseline after shared contract/scene changes and targeted independent
checks for the feature. A match-flow fixture may exercise combat through its
public commands; fix a demonstrated combat defect as its own task rather than as
an incidental edit inside unrelated work. Do not shorten timers or set health to
claim natural gameplay acceptance. An isolated rules test may control its inputs
but must state that narrower scope.

Automated localhost tests do not certify human control feel, rendered behavior
or two-computer/internet play. Record engine/build/content version, exact checks,
known failures and unverified gates. For LAN, one player may host and the other
join its LAN IPv4 on UDP24567; use the chosen two- or four-player count. Each
person runs one game window. Hosted play follows the separately documented
service deployment and external connectivity checks.

At each handoff state: session/branch/base; implemented behavior; shared interfaces;
validation and limitations; paths still in use; next integration action. Historical
handoffs preserve evidence and authorship, but do not override current issue claims.
