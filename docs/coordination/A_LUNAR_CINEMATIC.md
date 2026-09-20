# Cinematic lunar environment — Dev A

Branch codex/a-lunar-cinematic, base 6c1eb0e. Custom Blender environment kit,
layered original materials, baked indirect light, dynamic sun/floodlights,
localized animated fog, synchronized vent/beacon, layered dust and pooled tracks.
Authoritative Moon surface, colliders, spawns, gravity, bot/control/network files
remain unchanged. A-owned arena scripts/assets/tests only; general project wiring
only if needed for offline baking, with no permanent editor plugin enabled.
Target RTX3080 native 1440p60 and <8GB total VRAM. First review a 12m showcase bay,
then extend its language around the octagon. Validation recorded before merge.

## Implemented and validated

- Eight original fractured rock meshes, a detailed ~12m service-bay section,
  and an editable Blender library/generator. Three outposts instance its authored
  kit with beveled framing, recessed airlock, glazing, tanks, pipework, roof
  machinery, grating, stairs and a gantry. Source images use portable paths.
- 768 fractured rocks divided into octant batches, denser terrain mesh and 4,800
  tiny cosmetic pebbles. Deterministic visual placement; physical geometry unchanged.
- Four original 2048² material sets; slope-blended, triplanar stone/regolith,
  micro normals, packed relief and weathered metal finish. Mipmapped VRAM imports.
- Committed LightmapGI data/atlas for the outpost kit, three indirect bounces,
  dynamic sun and floodlight shadows, three reflection probes. Receiver paths are
  explicitly checked. Indirect lighting rotates with reused modules; direct
  shadows remain world-aligned. No claim of a globally baked terrain landscape.
- Three localized, edge-faded animated dust volumes; global density and sky affect
  remain zero. Floodlight scattering is emphasized; moving beacons have zero
  volumetric contribution to avoid ghosting. Vent cycles modulate local haze and
  beacon energy on a shared timeline. Fine puffs fade at birth/death; coarse dust
  retains lunar ballistic motion. Atmospheric liberties are deliberate.
- Fine movement dust reads existing authoritative/replicated bot state. A 192-slot
  surface-mark pool emits paired tracks, aligns to the existing terrain and fades
  them after 18–35s. Airborne/stationary/eliminated bots stop emitting; removed bots
  release emitters/history. Decorative effects never affect physics/networking.
- Moon surface source change only binds the new visual material; height function,
  collider, rocks, spawns, gravity, bots and controls are unchanged.

Validation command: `tools/check-lunar-cinematic.ps1 -GodotPath <4.7.2 console>`.
Passed baseline, Foundry, camera boundary, Moon physical surface/replay/traversal,
headless exclusion, menu selection/layout, practice, Moon ENet reconnect/reset/
compatibility, Foundry four-client lifecycle, lightmap receiver and rendered effect
lifecycle checks. Reviewed showcase, arena and reverse 1440p captures plus movement.

RTX3080 / D3D12 Forward+ / 2560×1440 / 2×MSAA / uncapped / two moving bots:
1080 warmed samples across three views. p50 3.403ms, p95 4.774ms, p99 5.095ms;
engine peak tracked video allocation 1687MiB; highest system-wide GPU memory sample
3430MiB. GPU samples taken per view; not a continuous hardware memory trace.
Both requested thresholds passed on this machine; numbers are fixture-specific,
not a guarantee for different GPUs, player counts or future bot assets.

The pinned renderer prints a shutdown warning about seven leaked texture RIDs;
no missing bake receivers, script errors or runtime errors remain in the accepted
render run. Earlier editor automation attempts produced bake/editor errors; their
outputs were replaced by the correctly bound bake and that automation was removed.
Rebuild with the documented standard editor bake workflow in art_source/lunar/README.md.

A pre-existing parser failure in the A-owned optional hosted-server wrapper was
exposed by editor import. Its inferred dynamic `worker` variable now has an explicit
Node type; behavior unchanged. No hosted deployment was performed.

Local ignored evidence: battlebots/exports/lunar-review/{showcase,arena,reverse}.png,
benchmark.json and validation.log. Custom assets, bake, imports, sources and test
runner are committed; exports/caches are excluded.
