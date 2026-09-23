# Heat-only combat resources — B, 23 September 2026

Task: [#41](https://github.com/fumbleforce/battlebots/issues/41).
Checkout: `/tmp/battlebots-heat-only` (isolated clone).
Branch: `codex/b-heat-only`; session `b-heat-codex-x3d-20260923-1345`.

## Requested behavior

Remove battery from runtime combat, derived stats, the catalogue, saved selections,
network snapshots and UI. Keep one shared heat meter, existing weapon heat rates,
weapon cooldowns and installed-power construction budgets. Nitro generates 14
heat/second, charged jump generates 20 heat on release, and self-right generates
30 heat on activation. Heat caps at 100 and locks heat-generating actions until
it cools to 50. Normal driving remains available. A committed discrete action
may reach the limit and complete; later actions are blocked.

Cooling remains 12 heat/second (15 with Cooling Pack), once per simulation tick
when no heat-generating action is active. An idle primary must not cool behind
an active auxiliary or Nitro. Jump charging is free; cancellation must not
launch or generate heat. Self-right keeps its existing eligibility and cooldown.

Known saved Battery Pack selections migrate to Cooling Pack, preserving the
remaining parts, name and cosmetics. Unknown catalogue identities remain invalid.
Online peers still need identical catalogue/build/protocol identities.

## Work in progress

The combat/status HUD battery bars and comparison-panel battery capacity row are
removed. HUD state and native compact layout checks pass at 720p/1080p/ultrawide
and 100/125/150% text. Native captures show the heat meter filling the available
row beneath integrity. The runtime still uses battery pending coordinated edits;
this UI increment alone must not be released as heat-only gameplay.

Shared edits await the explicit splits on #41 with #36 (turret/catalogue/wire),
#32 (stagger/bot), and #34 (arena integration files). #38 agreed to resource-only
changes in `perk_abilities.gd`, preserving its new drive config. No ownership is
inferred from old timestamps or silence. A matching hosted release is required
after gameplay integration; no live restart is performed by this B task.

The new `heat_only_state.gd` regression fails as expected on the current runtime
(nine assertions); it is an implementation acceptance target, not a passing check.
This checkpoint must remain unmerged until the complete resource change passes.
