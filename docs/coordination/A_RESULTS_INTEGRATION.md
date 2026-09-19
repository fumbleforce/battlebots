# A integration of B results and hosted play

Owner: A. Branch `codex/a-results-integration`, based on hosted `2eefc31`.
Integrates B's published `cc49a15` results panel without changing authoritative
rules, result records, admission or matchmaking. The shared menu shell preserves
both online cancellation/error routing and B's results/rematch transitions.
The results fixture is added to the presentation runner.

Validation passed: baseline, detached results panel, actual online lobby
and real two-peer full match/rematch. The network fixture still reported B's
two ObjectDB leaks at shutdown. One verbose diagnostic run passed without the
warning, and no retained fixture object was identified. Existing teardown already
clears multiplayer mappings and verifies both viewports are freed; no speculative
cleanup edit was made. The intermittent warning remains unresolved.
Public deployment remains pending the
user's confirmation of the concrete Fly resources/cost. The preceding native
Godot shutdown failure remains open and must not be hidden by a passing retry.
