# A — free-for-all authority and session

Owner A; branch `codex/a-ffa`, based on tested/pushed 5v5 increment `e118f91`.
5v5 CI run 35462495199 failed the prior network presentation movement fixture;
see the validation notes below.

## Intent and ownership

Implement the specified 4–8-player custom FFA, one 300-second round, elimination
tick placements, timeout survivor/core/damage ordering and shared first-place
wins. At least four connected players, all admitted players ready, can start;
the selected count is the lobby maximum. No AI fill or mid-round admission.
Individual forfeit and any-survivor spectating apply in FFA. Team formats retain
their full-lobby and team-vote behavior.

Root owns networking/session, A app bootstrap, authority spawn selection, docs
and check scripts. Rules subagent owns MatchState and isolated FFA rule tests.
Network subagent owns an independent FFA session scene. No B UI, camera, arena,
assets, or modelling worktree changes. Use existing FFA_1 through FFA_8 markers.

## Planned shared contract

- `MvpSession.host(port=24567, listen=true, player_count=4, mode="teams")`:
  teams accepts 2/4/10; ffa accepts capacities 4–8. Existing calls unchanged.
- `MatchState.configure/begin(player_count, match_mode="teams")` and optional
  fourth `advance` argument `server_tick` support FFA without changing team rules.
- FFA bot `team` equals its unique entity ID so every other bot is hostile.
  `set_team` is rejected for FFA. Lobby `mode` is `ffa`.
- FFA match view adds `placements`: ordered entries `{entity_id, place,
  elimination_tick}` (-1 for survivors), and `winners`: entity IDs. Equal ranks
  share placement (competition ranking: 1, 1, 3). FFA `winner` is the sole winner
  entity or -1 for a shared win; consumers use `winners` to distinguish shared wins.
  Team winner/scores semantics stay unchanged. Detailed results retain these fields.
- Elimination ticks are observed after all same-tick combat, disconnect and
  forfeit decisions, before resolving winners. Tied last eliminations share first.
- `AuthorityWorld.spawn(..., team_size=2, mode="teams")` selects FFA marker
  slot+1 in FFA; no change to existing team marker mapping.
- Build handshake advances to `mvp-ab-5`, protocol remains 4.

## Acceptance

Independent pure rules cover timeout rounding/damage, survivor priority, tick
ordering, simultaneous eliminations, shared wins, 300 seconds, no overtime,
single-round results and reset. Independent actual ENet/UDP sessions cover
minimum/maximum lobby sizes, readiness, hostile combat, reconnect, forfeit,
spectator candidates, placement results and rematch. Preserve existing team,
contact and transport regression gates. Local tests do not close real-LAN,
human feel, ten-player combat performance, release services or soak acceptance.

## Validation in progress

- Pure FFA rules, existing team rules and physical 5v5 rules pass. FFA tests cover
  all 24 four-player roster orders, complete/two-way ties, earlier eliminations,
  survivor priority, rounded health, effective damage, no kill bonus and exactly
  18,000 active physics ticks (300 seconds). Rematch clears ranks/ticks/winners.
- FFA menu integration passed all capacities, four-player start below maximum,
  individual forfeit, any-survivor spectating and shared-win/local-place display.
- Independent dedicated FFA server plus four client processes reached active:
  `%TEMP%/battlebots-process-check-eb3bf727fbe54deda8d53ce60771149e`.
- The prior 5v5 CI failure occurred in an ENet presentation scene still running
  accelerated physics. All ENet integration scenes now use real-time 60 FPS,
  matching network scenes; the movement interval now counts physics frames.
  The >1 m movement assertion is unchanged. No competing input writer was found.
  Final full suite and new CI will verify the change.
- B's match HUD `d983612` and results intent `0f343f7` were inspected read-only;
  they are not merged here. B's results work consumes the preserved results event;
  FFA shared winners/placements need mode-aware presentation when integrated.
- FFA profile80 passed real hostile weapon contact, damaged reconnect, min/max
  admission, individual forfeit, authored spawns, shared placement and rematches.
  Separate `ffa_disconnect.tscn` passed expired reservation ranking, results-phase
  reconnect, four-player rematch after dropping an expired slot, and rejecting
  rematches below four players before returning to the lobby.
- First full suite passed new FFA at profile0, then stopped at the 5v5 profile80
  clock-ready assertion. Investigation is recorded in the integration handoff;
  `%TEMP%/battlebots-ffa-mvp.log` preserves the failure. Do not claim full-suite pass.
- Focused FFA profile150 also passed. Clock tracing identified unreliable ENet
  throttling after baseline delivery (5/32 throttle, up to eight pending clock
  requests, control budget only two). Clock request/reply now use reliable control
  at the existing one-sample-per-second rate; inputs and snapshots stay unreliable.
  Deterministic clock delivery and combined integration regression are pending.
