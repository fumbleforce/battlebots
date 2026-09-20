# A — player reconnect flow

Intent 2026-09-20, `codex/a-reconnect-flow`, base `50f3a63`.
A reserves session recovery APIs, original-theme reconnect presentation, general
menu composition and independent A network/presentation tests. B combat, bots,
garage and controls remain untouched. Server token rotation, damage retention
and the 20-second disconnect rule remain authoritative and unchanged.

Close the gap between the server's existing reconnect capability and the player
menus. Keep endpoint/token in memory after an unexpected disconnect, allow a
bounded retry of that same session, and clear credentials on explicit leave.
Never rejoin as a fresh participant when a reconnect is rejected. Preserve
hosted membership while recovering; only release it when the player leaves.
Show clear retry/progress/expired states and prevent arena controls while lost.

Acceptance: actual ENet reconnect preserves identity/damage and rotates token;
cancel and invalid/expired recovery cannot retain credentials; integrated game
menu returns to the existing round/results without submitting a fresh loadout.
Check native 720p/1080p panel layout and existing session/menu regressions.

## Delivered and verified

`MvpSession` exposes bounded manual retry, in-flight status and local time left.
Explicit leave/new session, server rejection and real wall-clock expiry erase
recovery credentials. A successful retry receives the server's original bot,
baseline and rotated token; no fresh loadout is submitted. No wire/build change.
The menu preserves hosted membership, hides stale HUD/input, and restores either
the current round or authoritative results. Leave remains keyboard-accessible
when retry expires. ENet publishers now skip connections already closing, fixing
packet/channel errors observed by the independent dropout fixture.

Godot 4.7.2 / Jolt checks:

- Baseline import/smoke: PASS.
- Independent reconnect session: PASS, including real 20-second expiry, identity,
  authored damage retention, rotation, explicit cancel, obsolete/revoked-token
  rejection. Failed-attempt timing uses an explicitly injected transport-failure
  signal; other admission/dropout checks use real ENet.
- Composed client game reconnect: PASS through active-round loss/retry, two public
  forfeits with normal intermission/countdown, results-screen loss/retry and leave.
  Hosted membership retention uses configured service state, not an external HTTP
  service; hosted admission is separately covered by its real ENet regression.
- Existing menu-game-network, online-menu, hosted-admission, clock-sync and session
  smoke regressions: PASS. No native crash/packet errors in final checks. Some runs
  retain the previously recorded two-object shutdown warning; it is not fixed.
- Detached reconnect panel logic/layout and rendered 720p/1080p review: PASS.
  Screenshots remain local Godot user-data `a-reconnect-*` files.

Fixtures are registered in the presentation/MVP runners with real-time transport
timing. Human recovery feel and external hosting remain unverified. Rebuild the
deployment export from updated main before deploying; earlier prepared artifacts
do not contain this recovery increment. Fly cost confirmation remains pending.
