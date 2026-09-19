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

## Necessary integration correction found by the real game test

The remote team API rejects every valid team selection: JSON decodes 0/1 as floats,
but _handle_request checks strict membership in the integer array [0, 1].
A Godot probe confirms float 0 equals numeric 0 but is not a member of that array.
B makes one intentional A-owned fix: accept only numeric values exactly equal
 to 0 or 1, preserving server authority and rejecting fractional/non-numeric inputs.
The actual ENet team-change test proves it. This changes no wire/API contract;
A should carry the same guard when integrating its contact-reconciliation branch.
The playable B frontend also includes Practice and real arena input/combat.

## Playable result

B lobby game now runs actual Practice and real two-peer host/join/ready into the
arena. Gameplay tests prove input moves the authoritative bot, spins the weapon,
and damages the opponent. Menus/settings suspend input and return to gameplay.
Starter acknowledgement handles JSON schema numbers without false pending states.

Rendered combat exposed a second real playability bug: an opponent over the camera
anchor collapsed the camera into the player's chassis. B's camera now finds a
bounded higher clear pivot, constrained by world walls/ceilings. The reproduced
camera recovered from 0 m to 5.97 m; dedicated contact/ceiling regressions and the
rendered combat scene verify the fix.

Baseline, content/rules/combat/stress and app checks passed. The legacy check-mvp
runner failed its accelerated ENet presentation test; that same test passes at
real-time --max-fps 60, consistent with A's transport-timing finding. B's new lobby
transport tests therefore use real time. Full runner success is not claimed.
Final evidence: all 14 B presentation checks PASS. Existing A network presentation, session profiles 0/80/150, duel and navigation checks all PASS with --max-fps 60; accelerated runner failure remains recorded above.
