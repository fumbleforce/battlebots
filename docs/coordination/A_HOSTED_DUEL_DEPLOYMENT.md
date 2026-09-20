# A — external hosted duel acceptance

Intent 2026-09-20, branch `codex/a-hosted-duel-deployment`, base `bca152c`.
A owns deployment/service configuration, hosted test harness and independent
client fixtures. Extend acceptance to an external HTTPS allocator and actual
assigned UDP server, including 1v1 results and rematch. Explicitly distinguish
forfeit-driven lifecycle evidence from natural combat. B's controls, combat,
bots, garage and wire contracts remain unchanged.

Prepare fresh Linux/Windows workers, run service checks and local exported-worker
acceptance before provisioning. Fly account inventory confirms the proposed
`battlebots-fumbleforce` app does not yet exist. The existing handoff records
pending confirmation of billable hosting. Public endpoint stays unconfigured
until deployment and external assigned-session validation pass.

The intended footprint is one Stockholm shared 2 CPU / 2 GB Machine, dedicated
IPv4 and four bounded UDP worker ports; no automatic scale-out. Other modes
remain deferred. Coordinate all deployment evidence and remaining acceptance here.

## Preparation evidence

The subsequent [1v1 Quick Play increment](A_DUEL_QUICK_PLAY.md) extends every
`--duel-only`/external run to both private and queued two-player matches. Evidence
below records the earlier private-only preparation.

- Service unit/integration tests: all 19 passed.
- Fly configuration validation: passed; authenticated account inventory confirms
  there is no Battlebots app yet. Existing unrelated apps were not modified.
- Fresh Linux dedicated-server and Windows release exports prepared successfully
  with Godot 4.7.2. Docker and a WSL distribution are unavailable locally, so Linux
  runtime acceptance remains a deployment check, not inferred from export success.
- Source-worker private duel: two independent HTTP/ENet clients drove, received
  matching 0-2 scores and two-round results, then entered the same active rematch.
  The rounds use public forfeit requests, not authored health or shortened clocks.
- Exported Windows-worker private duel also passed the same results/rematch flow.
  This validates release startup rather than relying only on editor/source mode.
  Source report: local temporary `battlebots-hosted-8M29pL/report.json`; exported
  report: `battlebots-hosted-5Wt7bq/report.json`. These reports contain no tokens.
- Final exported-worker default regression passed private duel plus the retained
  four-client queue (`battlebots-hosted-FM20wP/report.json`). Final assertions also
  verify the winner is the non-forfeiting authoritative team, not an entity-ID
  guess. Both peers moved 11.48 m; admission config files were removed after exit.
- JavaScript syntax, rejection of an HTTP external endpoint and Git whitespace
  checks passed. Runtime implementation, scenes and shared contracts are unchanged.
- External mode requires an HTTPS origin, rejects redirects, and never launches a
  local service. It releases its own reservations and removes admission files on
  exit; no credentials enter the retained report. Actual external execution is
  still pending provisioning.
