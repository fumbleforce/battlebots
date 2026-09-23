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

The 240-frame, two-bot RTX 3080 sample at 1600×900 measured render GPU median
5.798 ms / p95 8.372 ms and render CPU median 0.629 ms / p95 1.089 ms. Wall frame
timing was 6.029 ms / 38.455 ms in the presence of another independently launched
game process; this is not an isolated whole-game 60 fps certification. About
1757 MiB engine video memory and 2152 draws include bot/shadow costs. See
[hashes and scoped validation](evidence/foundry-reference-2026-09-23/validation.json).
Seven Texture RID allocations are reported at fixture shutdown both before and
after this change, without script/shader errors; existing issue #18 tracks renderer
cleanup. The upgrade does not claim to resolve that unrelated diagnostic.

## Matching release — 23 September 2026

Linux server and Linux/Windows clients were exported from clean source
`1a994a0a13171a01f69a69a210629c9cd3fc0f69`, using pinned Godot 4.7.2. Independent
SHA256 verification passed for every artifact; the native exported Linux client
launched and exited without script/shader/crash diagnostics. Windows was
exported, not launched on this Linux machine. Local client packages are
`battlebots/exports/battlebots-linux-1a994a0.tar.gz` and
`battlebots/exports/battlebots-windows-1a994a0.zip`.

The actual production container passed private/Quick Play driving, transport
reconnect, agreed results and active rematch. That same tested image is deployed
to the existing single Stockholm machine `287e605ad7d578`:

`registry.fly.io/battlebots-fumbleforce@sha256:b42f60aa1f5f9727be7c0b7313751d27287d4e89df322ae1bdf49dfb9d70bc11`

Live worker build-record equality and client/server compatibility were checked:
`mvp-ab-15`, protocol 6, catalogue 10 hash
`623a35b272a0d70feb57b7d4f0d0f298234b9608ab7ac4414945bec8404bd0ed`.
Presentation-only changes do not require a gameplay compatibility bump; source
and artifact records distinguish this release from the earlier build15 package.

The user had authorized the playtest break/restart. Prior image retained for
rollback:
`registry.fly.io/battlebots-fumbleforce@sha256:cbf2f8b87debb586b2e2c94a9977d57c3dda3b15ef37e95a43489e6b7b1c3ff4`.
Artifact hashes, local-container acceptance and live release checks are in
[release evidence](evidence/foundry-reference-2026-09-23/release.json).


The external check against `https://battlebots-fumbleforce.fly.dev` also passed
private and Quick Play driving, real reconnect, two agreed round results and
active rematch. See [external evidence](evidence/foundry-reference-2026-09-23/external-duel.json).
These checks resolve rounds with public forfeit votes; they establish deployed
lifecycle/connectivity, not natural combat or two-human feel acceptance (#6).
