# Sunreach Ruins — #101

New selectable Practice / Practice Duel / private LAN arena, inspired by the
user's sunny painterly ruin-basin reference. Actual terrain and collision,
15 m timber bridge decks, animated turquoise water and waterfall, layered cliffs,
weathered stone cover, broad leaf trees, conifers, windblown grass and wildflowers.
The central fighting lanes accommodate existing giant robots. Streams are
traversable and the ruin cover is static. Existing bots, weapons and destruction
were not replaced.

Source and regeneration: [Sunreach art source](../../art_source/sunreach/README.md).
Authoritative inputs: `battlebots/data/sunreach/layout.json`, `arena_spawns.json`.
`sunreach_ground.gd` reads renderer-independent baked heights/hulls. Scene art
has no collision. Build mvp-ab-55, arena rules 3, protocol 17, catalogue 19.

## Validation

- Sunreach arena: independent Jolt terrain sampling, all 18 spawn clearances,
  continuous bridge support, art/deck heights, bake input hashes, headless
  presentation stripping.
- Actual Bracken driving: both bridges crossed in both directions using ordinary
  throttle; no position correction or velocity injection during traversal.
- ENet session: host-selected arena, incompatible arena rules rejection,
  replicated collision/normal gravity, reconnect, round reset, unknown ID rejection.
- Baseline, all-arena spawn, heavy-robot spawn, Practice Duel, selection layout at
  1280×720 / 1920×1080 and 100% / 150% text, stale class cache startup.
- Linux Server exported PCK: required nested JSON and binary terrain samples exist;
  instantiated arena builds terrain and structures successfully.
- Offscreen Vulkan captures: overview, Bracken chase, bridge, ruin detail and battle
  in ignored `battlebots/exports/sunreach-review/`. Selection image is a real capture.
- 12 armed bots plus Practice targets, 1920×1080 / 30 seconds on RTX 3080:
  432 turret shots, one elimination, no runtime errors; GPU median 8.1 ms,
  p95 27.5 ms; physics median 3.3 ms, p95 4.0 ms. Total frame median 56.7 ms,
  p95 85.3 ms in the instrumented stress harness. Another user's ComfyUI process
  held 6.6 GB of GPU memory; concurrent headless checks were also running.
  These are contention-affected observations, not a 60 FPS performance claim.

Art is reviewed against the supplied direction in the captures; user acceptance
of the style has not been presumed. No desktop game window was opened.
