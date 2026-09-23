# Heat-only combat resources — B, 23 September 2026

Task: [#41](https://github.com/fumbleforce/battlebots/issues/41).
Checkout: `/tmp/battlebots-heat-only`; branch `codex/b-heat-only`.
Session: `b-heat-codex-x3d-20260923-1345`.

The user explicitly authorized proceeding across previously reserved resource
hunks and resolving them through rebasing. Integrated turret, heavy physics,
world and VFX behavior remains owned by its respective tasks.

## Behavior

Battery state, capacity, costs, regeneration and depletion gates are removed.
Heat is shared across primary, auxiliary, Nitro, jumping and self-righting.
Weapons retain their existing heat rates; Nitro adds 14/s, charged jump 20 on
release, self-right 30 on activation. At 100, actions lock until heat cools to 50.
Normal driving remains available. A committed discrete action completes when
it reaches the cap; later actions are blocked. Existing cooldowns remain.

Cooling removes 12 heat/s, or 15 with Cooling Pack, once per idle tick. An idle
primary cannot cool behind an active auxiliary or Nitro. Jump charging is free;
cancellation cannot launch or generate heat. Recovery retains its existing
eligibility/duration/cooldown and generates heat once; subsequent idle ticks cool.

Known saved Battery Pack selections migrate to Cooling Pack, preserving all
other parts, name and cosmetics. Unknown catalogue identities remain invalid.
The part is no longer offered by Customize or match pickups. Installed power
remains a construction budget, not another runtime resource.

HUD battery bars and comparison capacity row are removed. Heat fills the
resource row below integrity. Garage summary shows cooling. Shared overheating
is shown even with a disabled weapon: `OVERHEATED / COOL TO 50%`.

## Shared contract and release

Catalogue 12, protocol 9, build `mvp-ab-19`. Snapshot slot 9 is now the boolean
shared overheat latch instead of numeric battery. Other indices and the 40-field
count are unchanged. BotView publishes `overheated` instead of battery_fraction.
Local perk prediction restores authoritative heat/overheat; drive replay respects
the latch and predicted perk costs. It waits for a fresh authoritative snapshot
to clear an existing lock. Part swaps retain heat/latch. Compatibility rejection
is preserved; no health-only server-manifest workaround is permitted.

A must prepare matching clients/workers from the tested integration commit,
deploy during an established playtest break and run external private/Quick Play
through results/rematch. No live restart or hosted readiness is claimed here.

## Validation

Godot 4.7.2 baseline and focused heat/migration/wire/prediction regressions pass.
Spinner, hammer, saw, minigun, rules/content and perk state checks pass; all
weapon physics checks, including cannon/plasma, pass. Pickup preservation across
all three arenas and Practice reset pass. Garage comparison, compatibility,
preview, layout and text checks pass. Two old five-slot test fixtures now preserve
perk slots so their overweight assertions exercise the intended validation.

Native compact HUD passes at 720p/1080p/ultrawide and 100/125/150% text. Native
Garage passes at 150% text with long names; reviewed screenshots show the heat-only
HUD and cooling summary without battery controls.

Local multiplayer join, snapshot recovery, pickups, reconnect and Scorpion
sessions pass. The natural duel passes through two rounds, results and an active
rematch in 102 seconds, with 16 authoritative hits delivered to the client.
These checks do not establish a matching live hosted release or human acceptance.

Catalogue SHA-256:
`cd9c94bd3563c9949e17f010423e0f970a288c54ac1ec6c2bf2298589ff0e909`.
The main release workflow now automates server deployment after container checks
and an empty-room break; its successful completion and matching client artifacts
remain release acceptance requirements. See #41 for integration/release evidence.
