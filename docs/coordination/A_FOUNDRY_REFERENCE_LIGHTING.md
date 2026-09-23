# Foundry reference textures and lighting

Issue [#27](https://github.com/fumbleforce/battlebots/issues/27), A / Codex / x3d,
branch `codex/a-foundry-reference-lighting`, base `fc43251`.

The user's supplied `image-1.png` is the visual target: weathered rolled steel
plates with seams/fasteners, fine scraping and polished abrasion, warm practical
light pools/reflections, dark upper steelwork, amber/cyan accents and localized
glow. The existing arena has weak surface response and excessive uniform haze.

Preserve the 100 m physical octagon, spawns, bots/controls and Moon. Change
Foundry presentation shaders, texture sources, lighting and captures. Native
views must prove overview, floor/grazing surface and real gameplay readability;
compare the same before/after camera. Check source/import/shader errors,
baseline/Foundry physical invariants and bounded frame performance. Refresh the
actual Foundry menu preview; do not use the reference as a fake runtime image.

A new built-in imagegen albedo supplies abrasion detail; shaders supply physical
material response and panel hardware. Source and prompt provenance are recorded
in the texture directory README. Permanent findings and final evidence follow.

## Implemented material and lighting treatment

The new generated steel albedo is layered with 2.5 m plates, dark joints,
recessed fastener rings, polished heads, chipped dielectric paint, oil and skid
marks. Deterministic per-plate orientation/offsets break repeated wear. Shallow
height-derived bump follows real view-space surface directions rather than
assuming box UV tangent orientation. Bare steel is metallic; paint, cloth,
seating and dark enamel are separate material classes. Upper walls receive
bolted sheet-metal frontage behind the existing signs and services.

Practical floods and crown lights use warm broad highlights; localized wall/roof
fills approximate reflected light so upper structures remain readable. ACES,
a bounded real reflection capture, gentler bloom and substantially reduced haze
replace the original flat brown veil. Gate accents use cyan/amber vertical strips.
No new physical bodies, changed arena dimensions, bot/drive code, catalogue or
wire/version changes. Moon retains its existing materials and preview.

The first pass was too glossy; reducing light energy, increasing the polished
roughness floor, reducing micro-bump, neutralizing base-color warmth and varying
plate sampling produced the reviewed result. Making all dark paint metallic
made the structure disappear; restoring its dielectric component and local fill
reveals construction without globally raising floor brightness.

## Native visual evidence and checks

[Supplied reference](evidence/foundry-reference-2026-09-23/reference.png),
[same-camera before](evidence/foundry-reference-2026-09-23/before.png),
[same-camera after](evidence/foundry-reference-2026-09-23/after.png),
[actual player camera with authored bots](evidence/foundry-reference-2026-09-23/player-camera.png),
[wall/lighting close view](evidence/foundry-reference-2026-09-23/wall.png).
The before/after fixture keeps legacy box bots for a controlled arena comparison;
the separate native tool uses real Atlas/Sawblade models and the unchanged
production orbit-camera interface. The larger 100 m arena remains the user's
prior requirement; this treatment matches surface/lighting direction, not the
reference's different room proportions or every scenic prop.

Reproduce from the repository root with pinned Godot, no PowerShell:

```sh
godot --headless --path battlebots --editor --import --quit
godot --headless --path battlebots --script res://tests/baseline_smoke.gd
godot --headless --path battlebots --script res://tests/presentation/foundry_arena_test.gd
godot --headless --path battlebots --script res://tests/presentation/moon_arena_test.gd
godot --path battlebots --script res://tools/capture_foundry_materials.gd -- --benchmark
godot --path battlebots --max-fps 60 --script res://tools/capture_arena_previews.gd -- --foundry-only
godot --path battlebots --max-fps 60 --script res://tests/presentation/arena_selection_test.gd -- --capture
```

All checks passed, including native shader compilation, flat physical shell /
spawn invariants, headless presentation exclusion and selector layout. The menu
asset is a fresh native Foundry capture. Generated source texture is 1254 square
with VRAM compression, mipmaps and anisotropic sampling; exact prompt/provenance
is in [the texture source notes](../../battlebots/assets/textures/arena/README.md).

The 240-frame, two-bot RTX3080 sample at1600×900 measured render GPU median5.798ms /
p95 8.372ms and render CPU median0.629ms / p95 1.089ms. Wall frame timing was
6.029ms / 38.455ms in the presence of another independently launched game process;
this is not an isolated whole-game60fps certification. About1757MiB engine video
memory and2152 draws include bot/shadow costs. See
[hashes and scoped validation](evidence/foundry-reference-2026-09-23/validation.json).
Seven Texture RID allocations are reported at fixture shutdown both before and
after this change, without script/shader errors; existing issue18 tracks renderer
cleanup. The upgrade does not claim to resolve that unrelated diagnostic.

Matching release evidence is recorded after artifact preparation and acceptance.
