# Foundry arena art — Developer A

Branch: `codex/a-foundry-arena`, base `ad1607d`, isolated checkout
`C:/Users/jorge/battlebots-arena`. Concurrent audio work in the original checkout
is outside this task.

Scope: arena scene, new arena-only visual scripts/materials and arena validation.
Reference direction: industrial steel fight cage, worn floor, warm floodlights,
spectator galleries, heavy trusses and original Foundry branding.

User follow-up requests a true octagon and great lighting. The final arena is a
regular octagon with 25 m inradius (50 m across opposing faces), 20.710678 m sides,
and 3 m collision walls. Diagonal faces satisfy |X|+|Z| = 25*sqrt(2).
Keep all eighteen spawn transforms and the existing arena scene path. The floor
collider remains at Y=0 with 50 m extent beneath the octagon.

Shared scene handoff: `scenes/ui/orbit_camera.tscn` must set the existing exported
`corner_chamfer` to `50 - 25*sqrt(2)` = 14.644661. The prior setting 2.0 allowed
five high-elevation camera cases outside the new arena; the existing physics
sweep alone cannot constrain a camera above the 3 m walls. No camera algorithm,
input or drive code changes. The existing camera/arena and stress fixtures get
new diagonal coordinates; the network wall fixture starts farther inside the
new diagonal and verifies octagonal containment. This is necessary arena
integration, not incidental controls work. The other A session is on practice
menus and explicitly leaves camera/geometry paths alone.

No combat/menu/audio edits. The new presentation root skips construction on
headless servers. Protocol 4/catalogue 4 remain. Build `mvp-ab-11` rejects older
square-map peers so server collision and local prediction geometry cannot differ.

Acceptance: pinned-engine import/baseline, existing camera/arena regression,
headless presentation exclusion, rendered overview and gameplay-height captures.
Record actual visual and performance evidence before integration; no claim of
photorealistic reference parity or hardware-budget acceptance without measurement.

## Implemented art

Eight armored cage bays, numbered recessed shutters, spectator seating and static
crowd silhouettes, original venue banners, ventilation fans, service pipework,
radial steel roof trusses and an octagonal suspended lighting crown. Warm overhead
spots provide the main fight lighting; alternating cool/warm perimeter banks,
gallery practicals, restrained bloom and volumetric haze provide depth. Four
overhead spots cast bot shadows. No animated flashing, hazards or collision debris.

Repeated architecture/crowds use material-batched MultiMeshes and have no frame
processing. Headless mode builds no decorative nodes. The generated albedo source
and full built-in imagegen prompt are documented in
`battlebots/assets/textures/arena/README.md`; floor seams, wear, skid arcs and safety
markings are shader layers. Texture import enables VRAM compression and mipmaps.

## Validation

Pinned Godot 4.7.2 / Jolt / 60 Hz. `tools/check-arena.ps1 -GodotPath <console exe>
-Capture` runs the import/baseline, headless arena and camera tests plus optional
rendered captures. Passed: BASELINE, FOUNDRY, PRESENTATION and rendered FOUNDRY.
Checks cover all eight equal face distances, all eighteen spawn clearances, no
decorative collision, no headless art construction, and camera containment at
walls/diagonals across yaw/pitch/zoom cases. The original camera setting failed
five new containment cases; the scene boundary override fixes those cases.

Actual ENet `tests/network/wall_contact.tscn` at 80 ms injected latency passed:
north and diagonal each sustained 121 contact samples, peak presentation error
0.021 m, settled immediately on release, and reversed clear by over 2 m.
No tolerances were relaxed. The older stress fixture's diagonal expectation is
updated; ten-player certification remains outside this user's active scope.

Three 1080p views on RTX 3080 / D3D12 Forward+ were rendered and visually inspected.
The 240-frame per-view sample reported median 1.34–1.76 ms and p95 2.21–2.65 ms;
these are local CPU-side frame intervals in a static two-bot arena fixture, not
a GPU timing measurement or full combat/minimum-hardware acceptance. Gate view
reported 102 draw calls. Captures are local ignored output under
`battlebots/exports/arena-review/`, not exported game packages.

Remaining: human gameplay/lighting review and lower-end hardware performance.
Bot model polish remains B-owned; the rendered fixture uses existing primitive
runtime bot visuals. No claim of photorealistic reference parity.

## Integration

Rebased cleanly onto audio/practice `c83d266`. The presentation runner retains
both sessions' tests. Combined import/baseline/arena/camera/render checks passed;
the practice reset fixture also passed with a real post-reset target hit.
The final combined render sample measured median 1.35–1.74 ms, p95 2.67–3.21 ms
under the same limited fixture conditions. Ownership-only branch `86abe77` was
integrated at the other A session's request. No unfinished tutorial was included.
The integrated four-client session smoke also passed its admission, loadout,
round/results/reconnect/rematch checks with build 11 (correction p95 0.142 m).
