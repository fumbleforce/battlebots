# A — 1v1 Quick Play and expired-session recovery

Intent 2026-09-20, branch `codex/a-duel-quick-play`, base `5015c7e`.
A owns public matchmaking, its client/online screen, hosted acceptance harness
and independent tests. B combat, controls, bot assets and garage remain unchanged.
Keep other modes/tutorial deferred; retain historical four-player tests without
exposing them as the active Quick Play flow.

`POST /v1/queue` gains optional `capacity: 2` for the active 1v1 queue. Capacity
four and the legacy empty body retain prior behavior; pools must never mix.
Health advertises `queue_capacities: [2, 4]`. The current client explicitly asks
for two and rejects a service without that capability before allocation, while
private games remain compatible. No Godot wire or bot contract changes.

The original-theme online panel offers 1v1 Quick Play, private create and code
join, with clear opponent-waiting/cancel states and scalable keyboard navigation.
An authenticated request rejected with 401 clears the expired token/membership
and permits a new user-selected action; it must not strand the UI behind a
cleanup requirement or replay a canceled allocation automatically.

Independent work: service queue validation/isolation tests; online panel layout
and interaction tests; hosted harness exercising a real allocated two-peer queue
through results/rematch. Parent integrates client capability/expiry handling and
real HTTP fixtures. Validate the source and exported worker as feasible, service
tests, rendered menus, presentation regressions and baseline before merging main.
Service restart still ends ephemeral allocations; persistence and external
deployment are separate outstanding work, not claimed solved by retry UI.

## Validation

- Node 24 service suite: 25/25 passed, including concurrent pairs, pool isolation,
  invalid requests, port reuse, cancellation and started-match protection.
- Real HTTP client tests cover capability rejection before allocation, explicit
  two-player payloads, expired action/poll recovery and cancellation races.
  The first capability test exposed JSON float versus Array.has strict matching;
  numeric comparison fixes that issue and both client tests now pass cleanly.
- Composed online-menu HTTP/ENet test passes Quick Play, expiry recovery, private
  create/cancel, real welcome/lobby and leave. Full presentation and baseline pass.
  Existing ObjectDB cleanup warnings remain; no native crash or script errors.
- Detached panel/headless and native D3D12 captures pass at 720p/1080p/4K with
  100/150% text. Reviewed the 720p/150% Quick Play layout and keyboard scrolling.
- Real source-worker private and queued duels pass, including driving, matching
  authoritative two-round forfeit results and active rematch. Local report:
  `battlebots-hosted-WEPnJw/report.json` under the user's temporary directory.
- Fresh Linux and Windows exports prepared. Windows release worker passed both
  duel paths with report `battlebots-hosted-eKJ8WI/report.json`. These tests prove
  lifecycle/connectivity, not natural combat, public reachability or human feel.

The user subsequently approved the prepared Fly deployment and its estimated
recurring costs in this conversation. Deployment follows this validated increment;
the earlier pending-approval note no longer blocks provisioning.
