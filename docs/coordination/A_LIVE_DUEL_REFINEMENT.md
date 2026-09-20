# A — live duel scoreboard and hosted recovery acceptance

Intent 2026-09-20, branch `codex/a-live-duel-refinement`, base `6bc839d`.
Previous goal turn deployed Fly, verified public private/Quick Play duels,
integrated the endpoint and released a matching Windows client.

A owns the general match HUD/menu composition and hosted recovery verification.
Add the missing held 1v1 scoreboard from spec section 3, consuming the existing
remappable `scoreboard` action. No B input collection, bindings, garage or bot
producer edits. B should remove the stale "planned" binding label after this
handoff. Match scores/timing come from accepted match views; identities/status
use public lobby and accepted bot views. No live combat totals are invented
from final-result-only statistics.

Use original menu theme, clear YOU/OPPONENT labels, scalable layout and keyboard
hold/release. Driving continues while held. Menus, settings, recovery, results
and focus loss suppress it; holding across a modal must not reopen it. Independent
detached, composed and real session tests cover data, interaction and rendering.
Related bounded fixes align hosted connecting copy and 1v1 result team labels.

Independent hosted tests add opt-in public reconnect acceptance to the existing
source/public private/Quick Play harness. Preserve membership, reconnect to the
same entity/match within the existing window, and never log credentials. This
does not certify two-computer human recovery or modify the running Fly service.

## Public recovery evidence

`tools/check-hosted.mjs --endpoint https://battlebots-fumbleforce.fly.dev
--duel-only --reconnect` passed private and queued duels against the existing
deployed worker. The first peer actually disconnects ENet and uses the public
reconnect API; both peers wait for the initial full baseline and recovery before
driving or voting. Private recovery took 568 ms; Quick Play recovery took 136 ms.
Identity, match, round, full baseline and idle core/zones were retained, and the
reconnect token rotated. Both duels then passed two-round results and rematch.
This checks idle health retention, not recovery during natural combat damage.
The observer's false reconnect fields mean it did not disconnect.

The [redacted report](evidence/fly-reconnect-2026-09-20.json) contains no admission
or reconnect credentials. Local source checks also passed both modes. No new Fly
resources, deployments or restarts were needed.

The subsequent manual playtest reopened menu presentation acceptance. See
[user feedback and ownership](A_PLAYTEST_MENU_FEEDBACK.md).
