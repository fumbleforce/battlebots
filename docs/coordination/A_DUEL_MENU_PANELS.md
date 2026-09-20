# A — 1v1 menu panels

Intent recorded 2026-09-20, branch `codex/a-duel-menu-panels`, base `1a56c38`.

A reserves general menu presentation: online screen, win/score presentation,
in-game menu composition in `scripts/presentation/menu_game.gd`, and independent
presentation tests. Align these screens with the supplied menu theme and panel
design. Existing session state remains authoritative; preserve cancellation,
settings, practice restart and rematch behavior. No B combat, controls, camera,
bot, garage or profile implementation edits are planned.

Parallel work is limited to disjoint online and results presentation files;
main integration owns the in-game menu. Shared runtime schemas stay unchanged.
B should continue its bot/combat/garage/control work without editing these
reserved general menu paths during this increment.

Validation planned: detached screen checks, real session/menu flow, practice and
audio regression checks, baseline after scene changes, and rendered 1280x720 and
1920x1080 review. Record actual evidence and limitations before merging to main.
External deployment and HUD expansion remain separate outstanding priorities.

## Implementation and validation

- Online uses original art/theme, private 1v1 create/join and visible service
  state/cancel/retry. Removed deferred mode controls from this player flow;
  existing service/mode implementations remain unchanged.
- Direct connect has labelled endpoint inputs, centered host/join/pending/error
  panels, and restores the original roster layout once connected.
- Results has win overview and score-detail tabs, authoritative final/per-round
  data, local team-based outcome and preserved rematch pending/leave behavior.
- Game menu composes the existing preview panel without changing B scripts.
  Original menu art/theme, context/score, settings, practice restart and leave
  remain. Arena overlays hide while it is open; diagnostics button-down remains
  operable while controls are released.

Godot 4.7.2 stable / Jolt validation on 2026-09-20:

- `tools/check-baseline.ps1`: PASS, including import and baseline smoke.
- New `game_menu_page_test`, `online_panel_test`, `results_panels_test`, and
  `lobby_panel_layout_test`: PASS; registered in the presentation runner.
- Rendered D3D12 1280x720 and 1920x1080 panel review: PASS. Local ignored game
  menu captures are under `battlebots/exports/menu-review/`; online/lobby captures
  under Godot user data; results captures under `%TEMP%/battlebots-results-*`.
- `online_menu_test`: PASS through real HTTP private-duel waiting/cancellation,
  then actual ENet welcome, selected-build submission and membership cleanup.
- `menu_game_network_test`: PASS through actual two-peer readiness, countdown,
  driving, menu suppression, rounds/results, local defeat, score page and rematch.
  This fixture uses forfeits to advance rounds; it is not natural-combat evidence.
- `menu_kit_lobby_test`, `practice_menu_test`, `audio_menu_test`, `menu_flow_test`,
  `menu_music_test`, `match_results_test`: PASS.

Visual review found HUD overlap, fixed by hiding overlays while maintaining
fresh practice data. Parallel code review found diagnostics hidden on button-down,
fixed with A-owned composition handling and an independent regression check.
Some runs report the previously documented two ObjectDB instances at exit; no
native crash occurred in this increment's checks. The intermittent engine issue
is not claimed fixed. No full combat suite, external internet deployment, or
human approval of this new menu design is claimed.

Integration: commit this increment, fetch/rebase with merges preserved, and merge
to shared main after the recorded checks. No B-owned implementation edits or wire
schema changes. Public `MatchResults.render` accepts an optional authoritative
local team, documented in CONTRACTS.md. Remaining A priorities: deploy hosted
1v1 and expand/refine its HUD; tutorial and other modes remain deferred.
