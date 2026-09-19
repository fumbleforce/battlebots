# B-07 — lobby presentation

Owner B. Branch `codex/b-lobby-presentation`, stacked on diagnostics `85dc14d`.
Runtime dependency remains A/B `bdb42ef` (mvp-ab-2/protocol 3). A's contact branch
`7235e50` publishes protocol 4 with unchanged public session APIs; it is acknowledged
but not silently merged. Peers must run matching builds.

## Intent before implementation

B will deliver a reusable lobby panel and session adapter: host/join/leave,
team rosters, readiness, starter loadout requests, build validity and connection
state. Readiness, team and accepted loadout are displayed only from session views.
Pending requests disable duplicate edits and surface failure or lack of confirmation.
Remote RTT will not be invented where the API only exposes connection state.

A retains app/bootstrap/live-session navigation ownership. The adapter emits
return/resume intentions; it neither changes scenes nor owns/deletes MvpSession.
A will mount the panel in place of its integration menu, not alongside it.
Until that mounting change, B provides a fully interactive independent lobby
scene with one session, one input producer and A's real gameplay behind it.
This increment does not claim the F5 app already uses the new lobby.

The supported service offers private LAN 2v2 and 1v1 only. Public matchmaking,
region/visibility controls, full 5v5/FFA and garage editing remain tracked scope,
not decorative controls that imply unavailable services.

Parallel work: subagent owns panel + GUI checks; another owns real-session tests;
B owns lifecycle-neutral adapter, independent playable scene, docs and integration
review. Validate read-only rendering, pending/invalid/phase-locked state, keyboard
flow, two-peer requests and 1280x720 rendering. No edits to A-owned runtime paths.
