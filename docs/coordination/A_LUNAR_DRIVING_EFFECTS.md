# Moon driving dust and diesel exhaust — issue #31

Session `a-lunar-dust-x3d-20260923-1238`, Codex on x3d. Isolated worktree
`/home/jorgen/repo/battlebots-rendering`, branch `codex/a-lunar-dust-exhaust`,
base `531f15a`. The user explicitly resumed the dust/exhaust follow-up after #29
and requested a worktree. Claims and cross-owner handoff are on
[#31](https://github.com/fumbleforce/battlebots/issues/31) and
[#32](https://github.com/fumbleforce/battlebots/issues/32).

## Delivered

Moon formerly emitted from offsets for the original small hulls. Both ballistic
and soft particles now originate at the two contact strips of the current
`collision_bounds()` footprint, using accepted presentation poses and terrain
height at each outlet. Forward/reverse movement shifts the trailing contact edge;
pivot turns scuff the ground. These are client observations of existing grounded,
velocity, angular velocity and elimination fields, with no physics/input changes.

Fine puffs grow, roll, curl and fade with soft depth intersections; heavier grains
follow lunar gravity. Track widths also follow the footprint. A maximum of 48
short-lived local FogVolumes leaves a lit trail in world space rather than dragging
one cloud behind each bot. Clouds spread and settle over 2.8 seconds. Global lunar
fog density stays zero. This is an artistic kicked-dust effect, not an atmospheric
or fluid simulation. Combat silhouettes stay readable.

Scorpion diesel keeps its two authored pipe-lip markers, engine-load response,
particle shader, sparse idle, stopping decay and reset API. Sixteen pooled local
volume cores add light-responsive depth under load, expand/rise from their deposited
world positions and dissipate over 1.8 seconds. Their lifetime advances independently
of new state observations, so shutdown does not freeze smoke in place. Existing
particles retain their 3.6-second fade. This adds diesel presentation only; it does
not add exhaust outlets to other bodies or change the separately owned nitro VFX.

GraphicsRuntime continues to scale GPU particle allocations and gate environment
volumetric fog. Fog-off/Low settings retain soft particles; native Forward+ is
required for volume cores. Headless scenes allocate no dust/fog visuals. See the
[Godot fog-volume guide](https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html)
and [fog shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/fog_shader.html).

## Bounds, cleanup and shared interfaces

- At most ten bot dust sources, each with two 180-puff emitters and two 96-grain
  emitters at High. Allocation follows existing Low/Medium/High/Ultra multipliers.
- Global Moon driving-volume pool: 48; ambient bay volumes stay separate.
  Scorpion diesel: 16 volume cores per bot plus its existing 256 High particles.
- Airborne, stationary, overturned and eliminated bots stop new dust. Existing
  clouds fade naturally. Teleports, accepted tick rollback, round reset, same-id
  bot replacement and removal clear stale trail state.
- LunarEffects owns both dust layers now; MoonVisuals no longer runs a duplicate
  per-bot loop. Tests consume LunarEffects' ballistic handles.
- `AuthorityWorld.weapons` replacement detects local round reset; same-id bot
  replacement detects baseline/live rebuilds. No world/session producer changed.
- Diesel configure/show_state/reset, stack attachment and `amount_ratio` behavior
  remain intact. No mvp_bot, nitro, camera, control, catalogue or wire edits.

## Validation and visual evidence

Pinned Godot 4.7.2, Vulkan Forward+, NVIDIA RTX 3080 on Linux:

- New native dust test checks real footprint separation/terrain height, remote
  movement, pivot and reverse contacts, world-space deposits, airborne/dead/stopped
  suppression, teleport cleanup, volume expiry/capacity, ten-source cap, same-id
  replacement, round reset/removal, Low/High budgets and fog toggle.
- Headless visual exclusion, baseline, Moon terrain/collision/gravity/replay checks
  pass. Native Moon test passes with `--fixed-fps 60`. An initial wall-clock FPS-cap
  run hit its frame-count-sensitive replay velocity assertion; physics source is
  unchanged. Use fixed frame progression for that rendering/physics fixture.
- Existing real-Jolt Scorpion diesel test passes headless and native: actual
  motion, both pipe-lip origins, load/idle/stop, world coordinates, elimination,
  same-pose reset, teleport and accepted tick rollback. Added assertions cover
  bounded/live volume cores and full shutdown expiry.
- Native moving review uses actual Atlas and Scorpion on Moon with the same
  scripted accepted remote circular path per preset. At 1600×900, High+fog GPU
  median/p95 = 4.832/5.685 ms; High particles-only = 4.757/6.584 ms; Low =
  3.829/4.622 ms. This is a bounded two-bot rendering fixture, not gameplay,
  network, low-end GPU or ten-player performance certification.

[Driving dust](evidence/lunar-driving-2026-09-23/high-fog-30.png),
[second moving view](evidence/lunar-driving-2026-09-23/high-fog-120.png),
[fog off](evidence/lunar-driving-2026-09-23/high-particles-only-30.png),
[Low](evidence/lunar-driving-2026-09-23/low-30.png),
[loaded diesel](evidence/lunar-driving-2026-09-23/scorpion_diesel_walking.png),
[shutdown](evidence/lunar-driving-2026-09-23/scorpion_diesel_shutdown.png),
[cleared](evidence/lunar-driving-2026-09-23/scorpion_diesel_cleared.png),
[GPU samples](evidence/lunar-driving-2026-09-23/performance.json),
[validation records](evidence/lunar-driving-2026-09-23/validation.json).

The known seven native Texture RID warning remains #18. The headless diesel
fixture reports one AudioStreamWAV and two playback references at shutdown; no
audio code changed. These warnings are recorded separately from passing behavior.

Reproduce from this worktree without PowerShell:

```sh
godot --headless --editor --path battlebots --import --quit
godot --headless --path battlebots --script res://tests/baseline_smoke.gd
godot --headless --path battlebots --script res://tests/presentation/lunar_driving_dust_test.gd
godot --path battlebots --script res://tests/presentation/lunar_driving_dust_test.gd
godot --path battlebots --fixed-fps 60 --script res://tests/presentation/moon_arena_test.gd
godot --path battlebots --fixed-fps 60 res://tests/presentation/scorpion_diesel_test.tscn
godot --path battlebots --script res://tools/review_lunar_driving.gd
```

## Matching release

Runtime source `2d030fd00c9e5fb4bae0320a658e2279c540c647`: Linux server and
Linux/Windows clients built from the same clean source with pinned Godot 4.7.2.
Artifact hashes verified independently; Linux exported client launch/exit passes.
Windows is exported, not natively verified here. Two initial automated launches
printed native Window focus/tree signal disconnect diagnostics; current source,
verbose export and final ordinary export reruns were clean. No UI fix is claimed;
the intermittent observation is tracked on #8 and in validation evidence.

Production-container private/Quick Play duels passed before deployment. Deployed
that exact tested image to the existing single Fly Machine `287e605ad7d578` in
Stockholm during the authorized playtest break:
`registry.fly.io/battlebots-fumbleforce@sha256:11cbf0c2bbab30710a63065f943ce57401dcee8d55b83fb805c6578ce62f831d`.
Rollback retained:
`registry.fly.io/battlebots-fumbleforce@sha256:99e3d41900bc524d9ecf47978aba5408b7d231e5c787db218e919a52ec54aad8`.
The live worker build record exactly matches the local server. All clients match
`/healthz`: build `mvp-ab-15`, protocol 6, content hash
`623a35b272a0d70feb57b7d4f0d0f298234b9608ab7ac4414945bec8404bd0ed`.
One Machine is started with the expected digest.

External private and Quick Play duels passed driving, actual transport reconnect,
two rounds resolved through public forfeits, matching results and active rematch.
These are deployment/lifecycle checks, not natural combat/human acceptance (#6).
Moon visual behavior is covered by the separate native fixtures above; public
Quick Play continues to use Foundry.

[Artifact/image/rollback records](evidence/lunar-driving-2026-09-23/release.json),
[container report](evidence/lunar-driving-2026-09-23/container-acceptance.json),
[external report](evidence/lunar-driving-2026-09-23/external-acceptance.json).
Local archives in this worktree: `battlebots/exports/battlebots-linux-2d030fd.tar.gz`
and `battlebots/exports/battlebots-windows-2d030fd.zip`.
The exact exported source is retained as Git tag
`release/lunar-effects-20260923-2d030fd`. During final integration, B #37's Garage
loadout links landed on main (`1461afc`). The rebase changed only those unrelated
client-menu files and preserved both concurrent HANDOFF entries. Combined import,
baseline, Garage links and native dust checks pass. Main includes #37; these
explicitly versioned export archives remain the tested `2d030fd` release and do
not claim the later Garage links. Protocol/catalogue/authority are identical.
Other agents' #32 nitro/combat effects, #34 Woodland, #35 pickups and #36 turret
remain separate in-progress work at this checkpoint.
