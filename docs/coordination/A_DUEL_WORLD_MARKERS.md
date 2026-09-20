# A — Readable 1v1 world markers

Intent 2026-09-20, `codex/a-duel-world-markers`, base `fa99d97`.
A reserves a read-only world-marker presentation node, composed-game wiring,
HUD accessibility integration and independent presentation/session tests. Use
published `MvpSession.bot_views()` presentation poses and authoritative identity,
team and elimination state. No bot meshes, controls/camera implementation,
combat mechanics or wire changes. B's bot paint and weapon presentation remain
untouched.

Deliver distinct symbol/text badges for the local bot and rival in 1v1, and the
practice target. Respect depth so markers do not reveal bots through arena
geometry; render below HUD/menu layers. Existing color presets, high contrast
and text scale apply. Menus, results, recovery and unavailable baseline data
suppress markers. Other modes remain deferred, not a new expansion target.

Local API: `BotWorldMarkers.render(views, local_id, practice, duel)` and
`apply_accessibility(text_scale, palette, high_contrast)`. The game owner controls
visibility with the HUD. Independent tests should prove identity is not inferred
from entity-ID ordering, data removal clears markers, invalid poses are ignored,
and rendered labels remain readable without covering essential HUD information.

## Implemented behavior and evidence

Badges are fixed-size, unshaded Label3D billboards at global world-up 1.4m above
the published presentation origin. Distinct `+ YOU` and `◇ RIVAL`/`◇ TARGET`
text survives grayscale; eliminated views append `/ OUT`. Four HUD color presets,
100–150% text and white-outline high contrast apply on creation and setting changes.
Small reusable depth-tested stems link labels to a fixed chassis anchor; both
label and stem respect walls, and Canvas HUD panels render in front of them.
No bot paint/material or camera implementation was changed.

The game schedules marker reads after child bot presentation interpolation.
Baseline filtering remains in the existing `MvpSession.bot_views()` API. The
detached test checks swapped identity order, unknown local team/baseline, invalid
and degenerate transforms, disappeared peers, transformed marker parents,
ambiguous opponent data, elimination, resource reuse and deferred modes.
The real ENet combat-HUD fixture now also verifies marker baseline filtering,
host/client identity, elimination, round repair/reset and removal on leave.
The actual reconnect fixture verifies suppression during transport recovery and
restoration after baseline acceptance.

`world_markers_game_test` exercises actual practice, public driving commands,
displayed-pose following, HUD preferences, menu/settings suppression and leave.
Native D3D12 captures of both the detached scene and composed game were inspected;
detached captures cover720p/1080p/4K and wall occlusion, composed captures cover
720p/1080p. Local user-data files are `a-world-markers-*.png` and
`a-world-markers-game-*.png`; screenshots are validation artifacts, not assets.

An initial composed fixture with direct AudioPreferences/HudPreferences class
dependencies reported retained GDScript resources at exit. Bounded isolation
attributed each retained script to its corresponding direct dependency while
dynamically loading the game. The final fixture copies the game's published
preferences and omits an unnecessary audio restore in its isolated process;
all marker assertions remain. Ordinary quit and strict error/exit gates remain.
This avoids that fixture dependency pattern and is not a Windows engine-crash fix.

Final validation: pinned Godot4.7.2/Jolt baseline import/smoke and the full
presentation runner passed, including real network/menu/results/rematch/service
checks and the extended marker lifecycle assertions. Native D3D12 composed-game
capture passed without resource errors. Some full-run fixtures reported two to
five ObjectDB instances at exit; no native failure occurred in this run. Human
marker/low-vision acceptance and the existing Windows shutdown issue remain open.
Integrate this completed A presentation increment into main after fetch/rebase;
no network protocol, shared BotView fields or B implementation changes.
