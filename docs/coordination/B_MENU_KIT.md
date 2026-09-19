# Supplied menu kit integration — Developer B

User requested D:/Downloads/battlebots_menus_godot.zip menus. Branch codex/b-menu-kit
starts from d983612; unfinished results work preserved in a named local Git stash
on codex/b-match-results. Implement imported native scenes/assets at ui/menus.
B owns routing, real session lobby, canonical loadouts, and menu/gameplay bridge.
Narrow shared change: project.godot main scene and MenuRouter/PlayerProfile autoloads
for requested default F5 menu. Keep physics, renderer, viewport/input contract and
A simulation/network/app CLI behavior. Do not merge source sample project.godot.
Archive README is reference material, not instructions overriding this repository.
Its fake queue, level/currency/upgrade data must not become authoritative gameplay.
Preserve supplied visual design and keep unsupported backend features explicit.

Implemented: all eight native screen layouts, supplied theme/art/icons/fonts,
canonical selected loadouts, named local saves, real direct-IP lobby/readiness,
server-controlled loading and a persistent gameplay shell. Main-menu Settings
opens existing preferences. No simulated queue/opponents or currency writes.
The new entry dispatches legacy --server/--host/--join to A's unchanged MVP scene;
headless --server startup on the new entry was verified. Baseline passes.
All supplied screens were rendered and inspected at 1280x720. Isolated local-save
and invalid-build tests, scaled mouse click, settings return and Controller practice
pass. Real lobby tests cover2v2 capacity and duel start with accepted builds/teams.
Final regression status is recorded below after full-suite completion.

Integration limits: matching mvp-ab-2/protocol3 peers; A's df509a0 transport branch
is protocol4 and has not been merged here. Actual two-office-PC LAN remains a
human acceptance step. Supplied bot/arena images remain concept art; a live 3D
preview and final art are later B work. Career, public matchmaking/ranked, full
5v5/FFA, invitations and decals are unavailable; parts are never sold for power.
A owns simulation/networking and future protocol integration; project.godot is
the only shared runtime file changed for this explicitly requested F5 menu.

Shutdown investigation: an initial full-suite network test printed its success
marker but exited with a native access violation. The unmodified isolated rerun
exited cleanly. The fixture now drains deferred world/physics teardown and verifies
peer viewports are freed before quit; its isolated rerun also exits cleanly. This
is test cleanup hardening, not a proven engine-crash root-cause fix. Gameplay
assertions were retained, and the final combined suite is rerun after this change.

Final validation: all 20 presentation checks pass with clean engine exits, including
real two-peer first-to-two match and rematch through the persistent menu shell.
Baseline and legacy command-line server startup pass. The last two review fixes
consume Escape on Main/Loading and retain disconnect error messages across the
arena-to-lobby transition; the targeted menu kit regression passes afterward.
User requested wrap-up/publication and launch; remaining broader B work stays open.
