# Lunar Outpost — Developer A

Branch `codex/a-moon-arena`, based on `fe9f2f0`, isolated checkout
`C:/Users/jorge/battlebots-moon`. The user requested an octagonal Moon arena,
lighting/shadows/shaders, dust, pebbles, uneven terrain and different gravity.
The supplied moon.png is visual direction, not an implementation specification.

## Delivered

Select **ARENA** on the main menu, choose **LUNAR OUTPOST**, then **USE THIS ARENA**.
Practice and LAN hosting use that saved arena. Joining always uses the server's
arena. Foundry remains the default; public hosted servers remain Foundry.

Moon retains the 50 m octagonal boundary and all 18 team/FFA spawn markers.
Its deterministic 81 × 81 height field provides up to 0.58 m of rolling ground,
with flat spawn pads and a clear central practice area. Four small edge rocks
have collision; 900 tiny scattered pebbles are decorative. Outside the boundary:
crater ridges, 380 instanced boulders, eight flood towers, service buildings,
satellite dishes, solar arrays and catwalks. No decorative meshes are built on
headless servers. Ground collision is identical on server and clients.

Lighting combines low-angle warm sunlight, cool shadow fill, shadowed floodlights,
ambient occlusion and restrained glow. Generated regolith and Earth textures are
committed with import metadata and provenance. Ground shading uses world-aligned
microrelief; Earth has a day/night terminator and atmospheric rim. The sky is black
with sparse stars; there is no atmospheric fog on the Moon. Moving grounded bots
shed bounded GPU particle trails following ballistic lunar arcs; airborne,
stationary and eliminated bots stop emission. Remote bots use replicated state.

## Shared handoff

This supersedes the initial cosmetic-only proposal following the user's request
for uneven terrain and gravity. A changes AuthorityWorld and session baselines;
B bot, control, camera, weapon and combat implementations are untouched.

- AuthorityWorld `arena_id` selects a whitelisted scene. `set_arena` rebuilds the
  world before the baseline spawns bots. Body gravity_scale is 1.62 / 9.8 on Moon;
  B's existing model_config already feeds that scale into prediction/replay.
- `MvpSession.host` adds a final optional `selected_arena` argument; `practice`
  adds a second optional argument. Both default to Foundry.
- Hello advertises optional `arena_rules: 1`; Moon hosts reject peers without it.
  Foundry accepts existing build-12 peers. Lobby/baseline include optional `arena`;
  missing baseline field means Foundry. Unknown arena IDs disconnect safely.
- Build `mvp-ab-12` / protocol 4 / RPC signatures remain compatible with deployed
  Foundry servers. No service deployment or public matchmaking arena option.
- Bot launches/falls and dust use lunar gravity. Existing weapon trajectories and
  tire-force tuning are B-owned and unchanged; low-gravity handling needs a human
  balance playtest. No new weapon physics or camera-control behavior is claimed.

## Validation

Pinned Godot 4.7.2. `tools/check-moon.ps1 -GodotPath <engine> -Capture` covers the
baseline, Foundry regression, camera/boundary contract, Moon mesh/collision
agreement (including triangle interiors), Jolt lunar acceleration and replay,
headless visual exclusion, persistence/menu layout, practice regression, real
ENet Moon admission/baseline/reconnect/reset/legacy fallback and full four-client
Foundry match/rematch lifecycle. Rendered tests inspect Earth and dust start/stop
and drive a physical bot while capturing the arena. Main menu tested at 100–150%
text and four resolutions; arena selector at 720p 100/150% text.

Rendered evidence is local ignored output `battlebots/exports/moon-review/`:
`moon-overview.png`, `moon-floor.png`, `moon-outpost.png`, `moon-dust.png`,
`selector-1.0.png`, `selector-1.5.png`. Reviewed on RTX 3080, D3D12 Forward+.
Menu preview `ui/menus/art/arena_moon.png` is an actual in-engine capture.
No low-end GPU performance or cross-machine human lunar playtest is claimed.

Final result: `check-moon.ps1 -Capture` passed all checks above, including physical
traversal over rolling ground. Rebasing onto B's published menu updates `9e54dcc`
was conflict-free. Post-rebase baseline, practice-menu and B menu text-game
integration checks passed; B's menu changes were retained. Git diff checked.
