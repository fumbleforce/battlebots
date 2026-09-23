# Heat relief: kill sprees, cooling zones, coolant (#67, #68)

User request (23 September 2026): killing an NPC should reduce heat and build
combos, so a killing spree can continue. The maps should have heat-reduction
areas to cool off quickly and spread-out cool-offs to pick up.

All tuning is in `data/heat_relief.json`, read through `HeatRelief`.

## Rules (authoritative)

- **Kill sprees** (`CombatState.credit_kill`): the credited killer is the
  latest attacker within 10 s, as for elimination scoring.
  - Each kill vents `heat_per_kill` (40) plus `heat_per_combo` (15) for every
    earlier kill still inside `window_seconds` (8 s). The combo caps at
    `max_combo` (5).
  - A kill always clears the overheat lock, and ordinary cooling is tripled
    (`boost_multiplier`) for `boost_seconds` (4 s).
  - The combo resets when the window passes or the bot is eliminated. Every
    kill counts, whether the victim is a practice NPC or a player.
- **Cooling zones** (`AuthorityWorld.cooling_zones`): four circles of radius
  7 m on the arena axes, at 0.44 of the half extent (±22 m in Foundry). That
  keeps them clear of the spawn lines and the pickup points.
  - Inside a zone a bot sheds 45 heat/s, even while its weapons run.
  - Zones sit on the terrain on the Moon and in Woodland.
- **Coolant canisters** (`AuthorityWorld.coolant_points`, pickup kind
  `coolant`): eight dedicated pickup points on a ring at 0.62 of the half
  extent, between the spawn bearings.
  - Each canister vents 60 heat, lifting the overheat lock if heat falls to
    the resume level, and returns after 15 s.
  - Canisters never roll parts or credits, and part points never roll coolant.

## Contract

The snapshot gains two fields, 45 in total:
- `spree`: an int from 0 to 99.
- `cooling`: a bool, true when the bot is in a zone or boosted.

PROTOCOL 14. Pickup state carries `kind: "coolant"` items.

## Presentation

- **`CoolingZoneVisuals`:** a frosted vent grate with a glowing cyan band,
  rising cold vapour, a light and a COOLING label.
- **Coolant pickups:** a frosty-white canister marker labelled
  "COOLANT −60 HEAT".
- **`SpreeBanner`:** "ELIMINATED / DOUBLE KILL ×2 / … / RAMPAGE" with the
  heat vented, whenever the local combo rises.

## Validation

- `tests/simulation/heat_relief_test` covers combo venting and the cap,
  overheat clearing, window expiry, the cooling boost and snapshot fields. It
  also covers a world kill credit, zone cooling while the weapon runs (90 →
  49 heat in 1 s) and canister collection.
- `match_pickups_test` and `pickup_session` now count the canisters.
- Native captures come from `tests/presentation/atlas_weapons_showcase`.
