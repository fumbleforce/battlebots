# Robot destruction explosion — B

Branch `codex/b-destruction-explosion`, based on main `b6135df`.
User request: destroyed robots should explode impressively.

B reserves MvpBot presentation wiring, impact debris budget integration, new
destruction visuals/shaders and isolated presentation fixtures. Add a bright localized ignition, rolling fireball, expanding
pressure ring, radial sparks, tumbling metal panels and lingering smoke over a
scorched wreck. Consume confirmed core destruction from existing BotView only.
Forfeits, disconnections and immobilization with remaining core do not detonate.
First observations of existing wrecks are silent; repaired/new-round state restores
the original materials. Keep the camera anchor and authoritative body unchanged.

No shared schema, catalogue, combat balance, audio, menu or network changes. The
effect belongs to each bot, renders in world space and survives the transition into
round results. At most two transient bursts are active per scene tree; debris has
no physics bodies. Headless authority constructs no destruction renderer.

## Implemented behavior

`BotDestructionVisual.configure(visual_root, size, excluded_meshes)` records visible
hull meshes and their original overlays. Existing weapon/drive damage surfaces are
excluded so each component retains its own damage presentation. `observe(BotView)`
establishes a silent initial baseline, then explodes once on a healthy-to-eliminated
edge with zero core integrity. Invalid/missing data cannot fabricate an explosion.
MvpBot skips remote observations until accepted remote state exists. This avoids
inventing a healthy frame from local defaults before a reconnect baseline arrives.

Nine animated fire lobes, ten rising smoke puffs, a fading pressure ring and one
short-range orange light produce the blast. Integer noise hashing avoids observed
D3D12 grid seams in the original floating-point sine hash. Sparks and eight tumbling
metal panels use two MultiMeshes per burst. Trails last at most 1.35 seconds;
panels shrink away by 2.1 seconds; the complete effect expires at 4.2 seconds.
Ballistic panels do not invent floor bounces under airborne robots. No screen
flash, camera displacement, collision, damage or sound is added by this component.

At most two bursts render concurrently. Their sixteen panels share the existing
twenty-piece client debris allowance with CombatImpactVisual, which trims its
fragments immediately when a blast starts and after later impacts. Fire, smoke,
sparks and light are separate bounded visual elements. Cleared pools are reusable.
Ordinary impact sparks retain their independent 64-spark cap; each blast adds up to
64 brief spark streaks. Burst roots ignore inherited transforms and disappear with
their owning bot. Reset/repair restores original overlays and rearms destruction.
The effect continues across the immediate round-results transition.

## Validation — Godot 4.7.2 stable

- `tools/check-baseline.ps1`: BASELINE PASS.
- `destruction_visual_test.tscn`: headless PASS for lifecycle, existing wreck,
  repair/null/reset, per-instance materials, hidden meshes, transformed parents,
  expiry/removal, two-burst bound and combined twenty-fragment budget.
- `destruction_runtime_test.tscn`: headless and native PASS for real authored and
  classic MvpBots, lethal CombatState damage, preserved collision removal/camera
  anchor, silent reconnect baselines and missing remote baseline handling. Native
  checks exercise actual MvpSession snapshot acceptance, duplicate/stale/wrong-round
  rejection, next-round repair and destruction. They inject valid wire records;
  they do not claim an external two-computer playtest.
- Existing component damage/mapping, impact visual/controller/game and camera
  round-lifecycle checks pass headlessly. New checks are in the presentation runner.
- Native D3D12 Forward+, RTX 3080, 1280x720: reviewed Foundry and Moon captures at
  0.08, 0.25, 0.7 and 1.5 seconds. TEMP/destruction-{foundry,moon}-{008,025,070,150}.png.
  Final capture run passes; the known seven-texture-RID renderer shutdown warning
  remains. The existing impact-game fixture reports its known ObjectDB warning.

No catalogue/protocol/build identity change or hosted service restart. This is a
source presentation increment, not a packaged client/server release. Human combat
readability and low-end/large-scene frame budgets remain playtest work.
