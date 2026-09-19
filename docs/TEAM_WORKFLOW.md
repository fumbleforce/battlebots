# Two-developer workflow — Project Battlebots

## Current division of labor

The user's revised split supersedes the original phase assignments and historical
ownership in older handoffs. This session is Developer A.

- **A: Menus, networking, game rules, game world, audio.**
- **B: Combat, bot assets (models and weapons), bot-customisation menus, player controls.**

General menus include main navigation, host/join, lobby, loading, match HUD,
results and rematch. Bot selection/customisation, garage editing and bot preview
belong to B; A integrates their entry/exit into the general menu flow.

Game rules include readiness, teams, countdown/round timing, victory/judging,
forfeit, disconnect consequences, results and rematch. B implements damage,
weapon attacks, resources, physical bot behavior and recovery. A consumes those
combat outcomes when advancing the match; A does not duplicate B's damage logic.

Game world includes arenas, environment, spawn locations, world lifecycle and
world collision. Bot collision/assembly and driving belong to B. Audio belongs
to A, including menu music and combat sounds driven by B's published events.
Player controls include input, driving and camera behavior; their control-specific
settings belong to B, while A owns the surrounding general settings navigation.

## Existing path map

Folders contain mixed responsibilities; follow feature ownership, not old names.

- A: scripts/networking/, session/allocation/identity/result services,
  scripts/simulation/match_state.gd and authority_world.gd, scenes/arenas/,
  general scripts/ui/ and ui/menus/ flows, presentation/menu_game.gd and menu
  router, assets/audio/, app bootstrap, project/export/CI integration.
- B: scripts/weapons/, simulation/combat_state.gd, drive_body.gd, drive_model.gd,
  mvp_bot.gd and baseline_bot.gd, scenes/bots/, bot models/materials, canonical bot
  parts and validation, garage/customisation screens and previews, PlayerProfile
  and LoadoutStore, input/camera presentation and control-specific settings.
- Shared interfaces: BotCommand, BotView, BotSource, loadout records and versioned
  content identity. A owns their network encoding/validation; B owns their combat,
  bot and control producers/consumers. Coordinate schema changes across both.
- Mixed dev scenes and fixtures retain their filenames. Their a_/b_ prefixes are
  historical, not permission to edit the other developer's feature. A owns
  match/network/world/menu integration tests; B owns combat/bot/control/garage
  tests. Coordinate any fixture that touches both.

Prediction is A networking that consumes B's drive model. A must not change the
physical drive model incidentally to fix prediction. Likewise, B must not bypass
server authority to repair a control or combat presentation issue. Changes to
project.godot input actions and shared scene wiring require a documented handoff.

## Coordination and branches

1. Read GAME_SPEC.md, CONTRACTS.md, HANDOFF.md and current shared task notes.
   The current user priority is playable 1v1/2v2; ten-player work is removed from
   active todos even though its original rules and implementation remain.
2. Use a separate local checkout and codex/a-* or codex/b-* task branch. Do not
   change the other developer's checkout or assume sessions share memory.
3. Record intent, owner, allowed paths and acceptance in docs/coordination/ and
   append to DEVELOPER_B_TODO.md's shared coordination log before overlapping work.
4. Do not edit the same scene/resource/binary or mixed-responsibility script
   concurrently. Integrate published commits and preserve unrelated local edits.
5. Commit each completed increment, fetch origin, rebase the task branch onto
   origin/main with --rebase-merges when preserving A/B integration history, then
   push the task branch. Verify conflicts and any changed tree before pushing.
   Use --force-with-lease only if an already-published task history was rewritten;
   never blind-force or force-push main.
6. When a branch is complete, merge it into shared main, preferably through a PR,
   after required checks and conflict validation. A pushed feature branch alone
   is not finished work. Keep main as the latest combined game rather than making
   the other developer locate a chain of unmerged task branches. Fetch the merged
   main and base the next task on it. Leave genuinely unfinished work separate;
   document any required-check or branch-protection blocker explicitly.
7. Update producer, consumer and isolated checks when changing shared contracts.
   Leave the other developer the exact API, behavior, source commit and evidence.

## Validation and handoff

Use pinned Godot 4.7.2 stable, Jolt, 60 Hz, meters, Y up and -Z forward. The Godot
root is battlebots/. Keep server logic independent of rendered UI. Mocks are
fixtures, never authoritative runtime implementations. Preserve source .uid and
required .import metadata; do not commit .godot/, credentials or export output.

Run the baseline after shared contract/scene changes and targeted independent
checks for the feature. A match-flow fixture may exercise B combat through its
public commands, but a demonstrated combat defect belongs in a B handoff rather
than an uncoordinated mechanics edit. Do not shorten timers or set health to
claim natural gameplay acceptance. An isolated rules test may control its inputs
but must state that narrower scope.

Automated localhost tests do not certify human control feel, rendered behavior
or two-computer/internet play. Record engine/build/content version, exact checks,
known failures and unverified gates. For LAN, one player may host and the other
join its LAN IPv4 on UDP24567; use the chosen two- or four-player count. Each
person runs one game window. Hosted play follows the separately documented
service deployment and external connectivity checks.

At each handoff state: owner/branch/base; implemented behavior; shared interfaces;
validation and limitations; paths still in use; next integration action. Historical
handoffs preserve evidence and authorship, but do not override current ownership.
