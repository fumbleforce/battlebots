# Project Battlebots

Godot **4.7.2 stable** / Jolt / typed GDScript. Two developers, one repository, separate local clones.

## Start
1. Clone the repository locally and install Godot 4.7.2 stable.
2. Import `battlebots/project.godot` into Godot.
3. Press **F5**. Choose **Host Game**, **Join Game**, **Practice**, or **Garage** directly.
4. Hosts choose a mode then create a lobby. Joining goes straight to the host address and port. Practice immediately uses the selected bot. The Foundry is the only map, so no map-selection step is required.

The user-supplied Godot menu kit is integrated at `battlebots/ui/menus`. Its eight
screens retain the supplied art/theme and use real loadouts and LAN session state.
Garage/Customize edit canonical free parts and save named builds locally. Settings
uses the real camera/control preferences. Concept images remain 2D; career,
ranked/public matchmaking, invites and decals are not implemented. Choose
**Host Game** for duel, 2v2, 5v5 or FFA; **Join Game** accepts the host's mode automatically.
See [menu integration](docs/coordination/B_MENU_KIT.md) and the kit's README.

## Work independently
- **A:** `battlebots/scenes/dev/a_simulation.tscn` — real drive/contact checks.
- **B:** `battlebots/scenes/dev/b_presentation.tscn` — arena/camera/UI with mock movement.
- **B playable game:** `battlebots/scenes/dev/b_lobby_game.tscn` — Practice or real LAN host/join/ready, then drive and fight. The separate earlier lobby fixture remains available; F5 uses the supplied menu kit.
- **B match HUD:** `battlebots/scenes/dev/b_match_hud.tscn` — frozen mock snapshots for independent phase/score/result inspection; Left/Right/Space cycles cases. The playable B game reads the real session.
- **B network diagnostics:** `battlebots/scenes/dev/b_network_diagnostics.tscn` — synthetic connection states and telemetry; live preview reads the actual session.
- **B controls:** `battlebots/scenes/dev/b_controls.tscn` — rebinding, saved input preferences and hold/toggle primary against real lifter rules.
- **B input/menu:** `battlebots/scenes/dev/b_input_menu.tscn` — real lifter rules,
  cancellation and keyboard menus without a network session.
- Read [handoff](docs/HANDOFF.md), [contracts](docs/CONTRACTS.md),
  [team workflow](docs/TEAM_WORKFLOW.md), and [full specification](docs/GAME_SPEC.md).
- Use a focused feature branch from main, or explicitly declare the published
  A/B integration as a dependency while it is ahead of main. Current B work is
  `codex/b-menu-kit`, stacked on match HUD/lobby/diagnostics/input. Published art
  is merged into the playtest branch; the separate modelling checkout is untouched.
- Example starting names (check existing branches before creating):
  `git switch -c codex/a-drive-controller` or `git switch -c codex/b-arena-camera`.
  These are examples; branches are not created by the baseline.

## Verify
From the repository root in PowerShell:

```powershell
./tools/check-baseline.ps1 -GodotPath "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"
```

The check imports resources, loads both sandboxes, checks contracts/input bindings,
and verifies the physical body settles on the floor. It needs no export templates.
Run `./tools/check-drive.ps1 -GodotPath "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"`
for the baseline checks plus headless Jolt driving, braking, contact, and input-failure checks.
For manual inspection use F5 for Practice/Multiplayer, or F6 on a development scene.
Escape toggles the current menu; leaving requires its explicit Main menu/Return button.
Run B's independent scene checks with:
`./battlebots/tests/presentation/check-presentation.ps1 -GodotPath $GodotPath`.
Public hosting is a later release task; MVP export presets are described below.

## Playable modes

Current menu correction: `codex/a-menu-flow`, based on `codex/a-b-playtest`, build `mvp-ab-5`, protocol 4.
Use the same branch/build on all peers. The older `codex/a-b-integration`
checkpoint remains available; it does not include the 5v5/FFA follow-ups.

The main menu separates hosting, joining, practice and garage. All multiplayer
modes use the same lobby, with an optional saved-build selector. WASD/Space drive/brake,
LMB powers the spinner or raises
the lifter (release fully charged to flip), RMB brakes/lowers, and R self-rights
when eligible. Select or customize a legal build in the garage before playing.
The spinner disc rotates with charge; lifter forks rise and flip from weapon state.
Escape releases controls and opens the menu; Resume recaptures the mouse.

Use Godot 4.7.2 from the repository root (replace `$GodotPath` with your executable):

```powershell
& $GodotPath --headless --path battlebots -- --server --players=2 --port=24567
& $GodotPath --path battlebots -- --join=127.0.0.1 --port=24567 --ready
& $GodotPath --path battlebots -- --host --players=2 --port=24567
& $GodotPath --path battlebots -- --host --mode=ffa --players=8 --port=24567
& $GodotPath --path battlebots -- --practice
./tools/check-mvp.ps1 -GodotPath $GodotPath
./tools/check-processes.ps1 -GodotPath $GodotPath
./tools/check-processes.ps1 -GodotPath $GodotPath -PlayerCount 10
./tools/check-processes.ps1 -GodotPath $GodotPath -Mode ffa
```

To check a Windows export, pass its `battlebots.exe` as `-GodotPath` and add
`-Exported`. Distribute the executable and its adjacent `battlebots.pck` together.

Choose 2 players (1v1, the default), 4 players (2v2), or 10 players (5v5) before
hosting. CLI hosts accept `--players=2`, `--players=4` or `--players=10`.
The host counts as a player unless started
as a dedicated server. Everyone in the selected player count must press Ready.
5v5 rounds last 240 seconds; duel and 2v2 rounds last 180 seconds. All team modes
use first-to-two wins, with a five-round draw cap. Empty slots are not filled by AI.
FFA offers a maximum of 4–8 players and starts when at least four have joined and
everyone present is ready. Keep Not ready while waiting for more friends. FFA is
one 300-second round, with shared placements for same-tick eliminations and shared
wins on a complete first-place tie. Forfeit eliminates only your bot. CLI selects
`--mode=ffa`; `--players` is the maximum (defaults to 4 in FFA).
Ready/Not ready is available only in the lobby, Forfeit round only during play,
and Vote rematch only at results. Reconnect is available through the session API.

### Try multiplayer on two computers

Use the same current game build on both PCs and the same LAN.
Open one game window on each computer. On PC A choose **Host Game → Private Duel
→ Continue → Host Game**. On PC B choose **Join Game**, enter PC A's Ethernet/Wi-Fi
IPv4 shown in the lobby (for example `192.168.1.20`) and join. The joining player
does not select a mode or map. Press **Ready up** on both PCs to start. Hosts can
instead choose Team Brawl (four players), Large Teams (ten) or FFA (4–8 maximum).
Each person needs one game window. A UDP tunnel also works with its public
hostname and public port entered separately in Join Game; internet play still
needs a real two-computer test.
Loopback `127.0.0.1` always means the computer where that client is running.

The default port is UDP 24567. If joining fails, check that the host is running,
both builds match and the computers can communicate on the same LAN. Windows may
need a Private-network firewall allowance for the game/Godot executable. Do not
disable the firewall or configure internet port forwarding for this office test.
If multiple host addresses are shown, choose the Ethernet/Wi-Fi address on the
same subnet as PC B, rather than a VPN or virtual-adapter address.

Exports: `Windows Client` and `Linux Server` in `battlebots/export_presets.cfg`.
Install matching templates, create `battlebots/exports/windows` and `exports/linux`,
then run `--headless --path battlebots --export-release "Windows Client"` (or
`"Linux Server"`). The dedicated-server feature automatically selects headless
server startup. The GitHub workflow pins engine/templates, checks official hashes,
runs the suite and exports both artifacts. Generated binaries stay ignored.

Read [CONTRACTS.md](docs/CONTRACTS.md) for B's API and [A_MVP_TASKS.md](docs/A_MVP_TASKS.md)
for implemented scope and remaining joint acceptance. Independent F6 scenes
`tests/simulation/five_v_five_rules.tscn`, `tests/network/five_v_five_session.tscn`
and `tests/network/results_delivery.tscn` exercise 5v5 rules/spawns, ten real
clients and complete five-round result delivery. Network tests must run in real
time, without `--fixed-fps` acceleration.
Independent `tests/simulation/ffa_rules.tscn`, `tests/network/ffa_session.tscn`
and the FFA menu integration test cover rules, impaired sessions and app flow.
The other weapon families, public identity/allocation, full performance/soak
acceptance and release polish remain future work. Local automated tests do not
replace the two-computer LAN and human control-feel playtest.

Published Flamebot and sawblade art is included for inspection. The game still uses
primitive combat visuals. Flamebot has a validated runtime GLB; the sawblade folder
contains Blender source and is excluded from Godot import until its runtime export
is ready. Neither changes combat stats or collision in this checkpoint.
