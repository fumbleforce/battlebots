# Supplied Battlebots menu kit — integrated game UI

Imported from the user's battlebots_menus_godot.zip. Native scenes, theme, icons,
Barlow fonts (OFL.txt), and concept artwork retain the supplied visual design.
SOURCE_README.md is the original reference, not current setup instructions.

F5 now opens scenes/dev/b_menu_game.tscn. The project retains Godot 4.7.2, Jolt,
60 Hz physics, renderer, 1280x720 gameplay viewport and InputMap. MenuHost scales
the authored 1920x1080 UI to fit; it does not rescale the gameplay camera/HUD.
MenuRouter and PlayerProfile are the only added autoloads.

- Main: Host Game, Join Game, Practice and Garage are separate actions.
- Host: choose duel, 2v2, 5v5 or FFA, then create the lobby. FFA maximum is 4–8.
- Join: enter address/hostname and UDP port directly; the host supplies mode/map.
- Practice: immediately start with the selected build. The only map is Foundry.
- Lobby: real host/join by IP and UDP port, team, accepted build, readiness.
  Both machines need matching build/protocol. No simulated opponents or queue.
- Loading: actual session phase and roster; server alone starts the round.
- Garage/Customize: canonical parts, legal build validation, paint, 12 named local
  saves through LoadoutStore. All functional parts are free. Invalid builds remain
  visible for repair. Save failures are displayed without replacing saved data.
- The shop layout presents available parts and build rules; no invented currency,
  paid power upgrades or unlock progression is persisted.
- Settings opens real camera/input preferences. Escape pauses input locally; the
  online match continues. Explicit return leaves the session.
- The supplied System Discovery track loops in menus and stops during gameplay.

Career, public matchmaking, ranked, invites and decals remain unavailable.
Images are supplied concept art, not live 3D bot renders. No extra arena hazards
or weapon types are implied by that art. Legacy A command-line server/host/join
routes remain available through the persistent shell's early handoff.

Independent tests: menu_kit_test.gd, menu_profile_test.gd,
menu_kit_lobby_test.gd and menu_game_network_test.gd under tests/presentation.
Run check-presentation.ps1 with the pinned Godot console executable.
