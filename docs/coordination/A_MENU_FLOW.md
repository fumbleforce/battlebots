# Menu flow correction — Developer A integration

Branch `codex/a-menu-flow`, based on published combined checkpoint `d417d7e`.
User explicitly requested correcting B's menu flows and adding the supplied
`System Discovery.mp3` as menu music. This is a coordinated integration change
to UI/presentation; the separate modelling checkout remains untouched.

Main actions are Host Game, Join Game, Practice, Garage, Settings and Quit.
Join opens address/hostname and UDP port immediately, without choosing mode,
map or bot. The server's baseline determines the mode and roster. Hosts select
duel, 2v2, 5v5 or FFA; FFA has a 4–8-player maximum. The lobby supplies port and
optional saved-build selection. The Foundry is the only map, so a map screen is
not part of any normal play route. Practice immediately uses the selected bot.
Garage is independent and Done returns to Main; customization/catalogue Back
does not accumulate circular history. Legacy standalone scenes remain available.

One lobby supports all modes. It shows connection actions only before connecting,
Back before joining, Cancel Connection while connecting, and Leave Game after
admission. Unknown joins do not invent mode/map/teams. Large rosters scroll;
FFA has neutral player labels, no team switcher and individual forfeit/results.
Selecting a different bot exposes Apply Build; authoritative acceptance resets
readiness without replacing the session. Both PCs still need matching builds.

Validation: baseline and focused menu, customization, HUD, route/teardown,
actual ENet joins for all modes, existing lobby compatibility and 1280×720
layout/input checks pass. New flow test is registered in the presentation runner.
No physics or wire-format changes. Real internet/tunnel play remains unverified.

The supplied System Discovery MP3 is copied intact into assets/audio/menu. It
loops at -16 dB in menus, continues across menu navigation/settings, and stops
for gameplay (including its pause/settings views). Returning to Main restarts it.
The music player belongs to the persistent menu scene and is freed with it.
The music lifecycle regression passes headlessly, including continuous menu
navigation/settings, stopping for practice/pause/gameplay settings and restarting
on Main. Source MP3 and copied asset have matching SHA-256 hashes.
Windows and Linux exports were rebuilt after music integration. The packaged
Windows main menu/music startup and server with four independent clients pass.
The updated Windows ZIP and both raw exports remain under exports/playtest.

After this export is ready, resume Developer A's remaining spec work on a
separate feature branch. Do not modify this packaged checkpoint in place.
