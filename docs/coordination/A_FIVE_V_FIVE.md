# A — five-versus-five authority and session

Owner A; branch `codex/a-five-v-five`, based on tested transport increment
`df509a0`. The preceding CI run 35460811964 passed validation, exports and process checks.
This is the next full-spec mode increment; FFA remains a separate follow-up.

## Intent before implementation

Support full ten-player custom team lobbies, five distinct existing Foundry
markers per side, 240-second rounds and the shared first-to-two/five-round-cap
rules. Require all ten slots connected/ready; preserve existing duel/2v2 defaults.
Expose the mode in A's existing host count selector and command-line host path.

Reserved A paths: `scripts/networking/mvp_session.gd`, `wire_codec.gd`,
`scripts/simulation/match_state.gd`, `authority_world.gd`, `scenes/app/`,
independent `tests/network/` and `tests/simulation/` mode scenes, check scripts
and coordination/contracts. No B UI/presentation/assets/arena/model edits.

Parallel ownership: one subagent implements pure round timing/spawn selection
and independent rule/physics checks; another implements the ten-client impaired
session scene. Root implements session admission/readiness, app wiring, docs
and combined validation. All share the existing working tree with disjoint files.

Planned compatible method extensions:
- `MvpSession.host(..., player_count=4)` accepts 2, 4 or 10; ten reports `5v5`.
- `MatchState.begin(player_count=4)` selects 180 or 240 seconds; no-argument
  callers retain the existing team format. Snapshot adds mode/capacity metadata.
- `AuthorityWorld.spawn(..., team_size=2)` uses existing markers 1 through 5
  for five-player teams; existing two-slot mapping remains markers 2 and 4.

The build handshake will reject older game builds before accepting ten-player
sessions. B may consume the existing lobby `capacity` and `mode`; team IDs stay
0/1, winner remains 0/1 or -1 for draws. Spectator and BotSource APIs stay intact.

Acceptance: ten real ENet clients reach distinct spawns; nine cannot start;
oversubscribed teams and an eleventh join are rejected; authoritative movement,
damage, reconnect, both round resets and full rematch work under raw UDP
impairment. Measure actual RTT/traffic; preserve existing 0/80/150 ms regression
checks. Report hardware and test scope honestly; local tests do not replace LAN
or human contact feel, and do not establish full release performance.

## Results scaling fix and B handoff

A serialization probe found that detailed ten-player result packets exceeded
the old 32 KiB receive guard: 43,348 bytes after two rounds and 94,492 after five.
The session now bounds reliable baseline/match state at 128 KiB. Frequent
`match_view.rounds` contains `{round, winner}` summaries; detailed per-round
participant records remain in the final `session_event("results", details)`
under `details.match.rounds[].participants`, with aggregate `details.participants`.
The full result is sent once on reliable control, then included in a reconnect
baseline when needed. Timer heartbeats do not repeatedly carry the detailed
history. Result events deduplicate by match ID; leaving clears cached results.

The new build is `mvp-ab-4`, protocol remains 4. Older build IDs are rejected by
the existing handshake. This changes session match-view detail delivery; B's
result UI should consume the results event rather than seek detailed records in
ordinary timer updates. Existing BotSource, camera/input and diagnostic semantics
are unchanged. Independent full-results/reconnect tests pass.

Full-suite transport testing also exposed cross-entity snapshot starvation:
one remote bot retained a tick 47 frames old during round reset while others
updated. ENet's channel-wide `unreliable_ordered` snapshot stream discarded
valid older packets for different entities when raw UDP reordered them. Snapshot
transport now uses plain unreliable delivery; the existing per-entity epoch/tick
guards reject stale or duplicated state. Input command transport remains ordered.
The independent `snapshot_reordering.tscn` sends actual ENet RPCs through the
raw relay, delaying entity A by 250 ms while entity B arrives first. With the
old ordered annotation, A never arrived and the test failed. With unordered
transport both entities arrive; an older tick for the same entity and duplicated
snapshot content are still rejected. The existing reset gate is unchanged.

## Validation

- Independent `five_v_five_rules.tscn`: physical ten-spawn/reset checks, 240-second
  rounds, overtime, simultaneous wipe, first-to-two and five-round draw cap pass.
- `five_v_five_session.tscn`: profiles 0/80/150 passed nine-ready/admission/team
  limits, actual ten-client baselines, ownership/damage, reconnect, both resets,
  three-round results and unanimous rematch. All packets used the loopback relay.
- `results_delivery.tscn`: a real observer received 52,392-byte complete results
  for five rounds/ten participants, 628-byte heartbeats and a 62,376-byte reconnect
  baseline. Full per-round/aggregate records and event deduplication passed.
- App menu selection and return to default duel passed, including matching 5v5
  metadata before readiness. The count remains 2 unless the host selects another.
- Dedicated server plus ten independent client processes reached active:
  `%TEMP%/battlebots-process-check-ec057d1beff04875be2a7025bad69785`.
  The default four-client process check also passed:
  `%TEMP%/battlebots-process-check-b8bfc619d7a345be9d0c0ecc1373dd4f`.
- Initial full-suite run stopped on the four-client raw-UDP reset starvation
  above. The same reset assertion passes after the transport-order change;
  final full regression passed. The failed run is retained as
  `%TEMP%/battlebots-five-mvp.log`, targeted rerun as
  `%TEMP%/battlebots-five-transport-order.log`.
- Adversarial ordering before/after logs:
  `%TEMP%/battlebots-snapshot-order-before.log` and
  `%TEMP%/battlebots-snapshot-order-after.log`.
- Final `tools/check-mvp.ps1`: MVP PASS, including baseline/import, physics,
  app navigation, clock/reset, results, adversarial ordering, wall/contact and
  four-/ten-client network checks at 0/80/150 ms. Log:
  `%TEMP%/battlebots-five-mvp-final.log`. Worst scripted contact settling was
  183.3 ms at 80 ms and 250 ms at 150 ms; the 250 ms gate remains unchanged.

Traffic measurements use a five-second active window with one bot driving and
nine idle, not simultaneous ten-bot weapon combat. The final profile150 fixture
measured 186–237 ms actual RTT, 84,515–86,132 bytes/s received downstream and
2,438–6,428 bytes/s upstream per client, including 28 bytes IPv4/UDP overhead per
datagram. The active window was 5.016 seconds / 301 physics ticks; the complete
three-round results packet was 35,556 bytes. Hardware:
Windows/Ryzen 9 9950X3D, Godot 4.7.2/Jolt, real-time 60 Hz; all client worlds share
one process. This does not close release performance/soak or real-LAN acceptance.
