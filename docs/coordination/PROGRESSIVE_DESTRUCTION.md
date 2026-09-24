# Progressive destruction and destructible props (#72, #71)

Asked for on 24 September 2026. The system must work on every model with no
per-model authoring. It should be deeply satisfying: players should be able
to tear opponents apart and be crippled in turn. The giant saw cuts things in
half, railguns shoot clean through weak enemies and props, and bombs blast
things into pieces.

User decisions:
- Halves and lost parts are physics debris. They lie on the arena floor until
  the round resets, collide with the world only, and stay within a client
  budget.
- Saws sever parts mid-fight and halve on the kill.
- Destructible Woodland props ship in the same pass.

Soft bodies stay out (#38 decision). Deformation is expressed through
authoritative damage stages and presentation.

## What is authoritative

| State | Where | Replicated as |
|---|---|---|
| Zone HP (armour faces, drives, weapon) and core | `CombatState` (unchanged) | snapshot fields 7–8 |
| Killing blow `{kind, point, axis, force}` | `CombatState.death`, set by `CombatWorld._apply_hit` | snapshot field 45 |
| Railgun over-penetration | `CombatWorld._railgun_path`, `turret_weapons.json` | normal hits and events |
| Broken props | `ArenaProps` (`data/arena_props.json`) | reliable `_props` RPC plus baseline |

Nothing else about destruction is authoritative, by design:
- Which wheel or panel came off is chosen on each client from accepted hit
  events. How many come off follows only the replicated HP.
- If a client misses an event, it may drop a different panel from the same
  zone. It never drops more or fewer.
- A joiner or reconnecting client sees the same count of lost parts, hidden
  without replaying the debris.
- A wreck breaks from the replicated death record plus the entity id, so
  every client gets the same pieces.

Functional consequences keep the existing rules: a drive pod at 0 HP gives
half drive and 60% steering, and a weapon at 0 HP is disabled. The visuals
now show those losses as parts leaving the bot.

## Generic presentation

1. **Cut shader** (`scripts/presentation/destruction_cut.gdshaderinc`).
   - A piece keeps the region inside up to four planes and outside one
     tunnel, all in the mesh's own object space, so the cut tumbles with it.
   - Back faces render as the charred inside of the hollow shell, and seams
     glow and cool over time.
   - `cut_tear` roughens a seam with the same noise on both sides, so
     neighbouring pieces still meet exactly.
   - `destruction_surface.gdshader` stands in for StandardMaterial3D, Atlas
     paint and Sawblade paint. It copies their parameters, so it needs no
     per-model setup.
2. **Wreck break-up** (`scripts/presentation/wreck_pieces.gd`, driven by
   `BotDestructionVisual`).
   - Every visible mesh is copied into pieces:
     - a mesh wholly inside a piece keeps its own material and gets the soot
       overlay;
     - a mesh across a seam uses the cut stand-in;
     - a mesh the stand-in cannot draw goes whole to the one piece that holds
       its centre.
   - Styles come from `data/destruction.json`:

     | Kill | Break-up |
     |---|---|
     | saw or grinder | two halves along the blade (grinder: ragged) |
     | railgun | a bore, plus a split along it when overkill ≥ `split_force` |
     | mortar or cannon | five Voronoi shards thrown from the blast |
     | blunt | three shards |
     | burn | two ragged halves |

3. **Part loss** (`scripts/presentation/bot_part_loss.gd`).
   - Pools come from each visual's `component_meshes()` (weapon, left and
     right drive), plus every mesh smaller than `hull_share` of the bot's
     volume, grouped by the face it sits on.
   - A pivot holding at most three meshes stays together, so a wheel leaves
     whole.
   - Thresholds are set in `parts`: components at 60/30/0%, armour at 50/0%,
     and core at 75/50/30/15% (from the struck face).
4. **Props** (`scripts/arena/arena_prop_visual.gd`).
   - A felled tree topples as physics and leaves a stump.
   - Barricade logs and beams scatter.
   - Boulders split into four rock chunks.
   - `WoodlandVisuals.prop_instances(name)` maps a prop to its batched
     MultiMesh instances.
5. **Debris** (`scripts/presentation/wreck_piece.gd`).
   - Collision layer 0 and mask world.
   - Evicted with `max_pieces` (48): the oldest sink into the ground.
   - Heat decay updates only the cut meshes.

## Adding a new bot model

Nothing is required for it to break and shed parts. For good results:
- Return its weapon and drive meshes from `component_meshes()`. Every visual
  already does, for the damage stages.
- Build wheels, legs and add-ons as pivot empties holding their surfaces. The
  kit's `X` / `XSurface` pattern already does this, so each comes off whole.
- Use StandardMaterial3D, Atlas paint or Sawblade paint on surfaces that
  should cut cleanly. Custom shaders still break, but whole.
- Add the model to `tests/presentation/destruction_models_test.gd`.

## Adding a new weapon

- Give its `_hit` an `axis` when direction matters for the cut, as for the
  saw blade.
- Map its event kind to a style in `data/destruction.json` `kinds`.
- Add prop multipliers, plus melee dps or hit for tools, in
  `data/arena_props.json`.

## Evidence (headless, 24 September 2026)

- `tests/simulation/atlas_turret_physics.tscn`: over-penetration through two
  weak bots into a third, and the death record surviving the wire.
- `tests/simulation/saw_physics.tscn`: a saw kill records the blade axle and
  the contact point.
- `tests/simulation/arena_props_test.gd`: a railgun fells a tree and hits the
  bot behind with the carried energy. It also covers saw felling time, mortar
  and ram damage, client adoption and the round reset.
- `tests/presentation/wreck_pieces_test.tscn`: plans, shard partition,
  determinism, mesh classification, cut parameters, the reconnect path and
  the budget.
- `tests/presentation/bot_part_loss_test.tscn`: clusters, hit choice,
  severing, armour stripping, repair and reconnect.
- `tests/presentation/destruction_models_test.tscn`: all 14 shipped models
  break (saw, rail, mortar) in under 8 ms each on this machine.

## Known limits and open work

- The look (glow, soot, speeds, tear) has not had a human review in a real
  window. Tuning lives in `data/destruction.json`.
- Destroyed bots keep a static box collider on the server, as before. Halves
  are cosmetic, so bots drive through them.
- Felled trees and props are cosmetic once broken and do not block bots.
- A Sawblade shattered by a mortar draws about 750 meshes until the round
  resets (its intact hull draws about 600). Merge pieces if profiling shows a
  cost.
- Terrain craters and arena perimeter walls are not destructible. Other
  arenas have no props yet.
