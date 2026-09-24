# Project Battlebots

Godot **4.7.2 stable** / Jolt / typed GDScript. One repository, separate local clones or worktrees per session.

## Collaboration

There are no fixed developer roles: any session may work on any area, coordinated
through GitHub issue claims and the [coordination board #2](https://github.com/fumbleforce/battlebots/issues/2).
The former A/B split in older notes is history; see [workflow](docs/TEAM_WORKFLOW.md).
Pushes to `main` deploy the hosted server automatically
([deployment](services/matchmaking/DEPLOYMENT.md)).

## Start
1. Clone the repository locally and install Godot 4.7.2 stable.
2. Import `battlebots/project.godot` into Godot.
3. Press **F5**. Choose **Host LAN Game**, **Join LAN Game**, **Practice**, or **Garage** directly. **Play Online** requires a deployed/configured service.
4. Hosts choose a mode then create a lobby. Joining goes straight to the host address and port. Practice immediately uses the selected bot. The Foundry is the only map, so no map-selection step is required.

The user-supplied Godot menu kit is integrated at `battlebots/ui/menus`. Its eight
screens retain the supplied art/theme and use real loadouts and LAN session state.
Garage/Customize edit canonical free parts and save named builds locally. Settings
uses the real camera/control preferences. Concept images remain 2D; career,
ranked play, invites and decals are not implemented. Public room codes and 1v1
Quick Play are live on the Fly-hosted playtest service. Choose **Host LAN Game**
for a local match; **Join LAN Game** accepts the host's mode automatically.
See [menu integration](docs/coordination/B_MENU_KIT.md) and the kit's README.

## Work independently
- **A:** `battlebots/scenes/dev/a_simulation.tscn` — real drive/contact checks.
- **B:** `battlebots/scenes/dev/b_presentation.tscn` — arena/camera/UI with mock movement.
- **B network diagnostics:** `battlebots/scenes/dev/b_network_diagnostics.tscn` — synthetic connection states and telemetry; live preview reads the actual session.
- **B controls:** `battlebots/scenes/dev/b_controls.tscn` — rebinding, saved input preferences and hold/toggle primary against real lifter rules.
- **B input/menu:** `battlebots/scenes/dev/b_input_menu.tscn` — real lifter rules,
  cancellation and keyboard menus without a network session.
- Read [handoff](docs/HANDOFF.md), [contracts](docs/CONTRACTS.md),
  [team workflow](docs/TEAM_WORKFLOW.md), and [full specification](docs/GAME_SPEC.md).
- Use a focused feature branch from main.
- Example starting names (check existing branches before creating):
  `git switch -c codex/drive-controller` or `git switch -c codex/arena-camera`.
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

Play from current `main`; the hosted service is deployed automatically from it.
Select Duelist for the hammer, or use Garage → Customize → Weapon for the saw and
other weapons. All peers must run the same build.

The main menu separates hosting, joining, practice and garage. All multiplayer
modes use the same lobby, with an optional saved-build selector. WASD/Space drive/brake,
Hold LMB to power the spinner/saw or raise
the lifter (release fully charged to flip); press LMB for a committed hammer strike.
RMB brakes/lowers, and R self-rights
when eligible. Select or customize a legal build in the garage before playing.
The saw needs sustained contact: 6 raw damage per third-second. Primitive weapon
visuals follow authoritative state.
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
./tools/check-performance.ps1 -GodotPath $GodotPath -DurationSeconds 300 -WarmupSeconds 30
# Full memory/traffic soak; headless runs do not certify rendered performance:
./tools/check-performance.ps1 -GodotPath $GodotPath -DurationSeconds 3600 -WarmupSeconds 600 -RequireSoak
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

The **Play Online** route supports Quick Play (1v1), private 1v1
games and eight-character friend codes through an externally hosted dedicated
server at `https://battlebots-fumbleforce.fly.dev`. Current clients
are configured to use it. The 2026-09-23 coordinated release is `mvp-ab-14`,
protocol 6, catalogue 10; older builds must update. See the
[current release and matching clients](docs/coordination/A_HOSTED_LINUX_RELEASE.md).
There is no built-in localhost fallback for players.
[Deployment instructions](services/matchmaking/DEPLOYMENT.md) describe Fly.io,
local checks, operating costs and the current single-Machine limits. LAN remains
available independently through **Host LAN Game** and **Join LAN Game**.

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

Read [CONTRACTS.md](docs/CONTRACTS.md) for the shared APIs and the
[issue board](https://github.com/fumbleforce/battlebots/issues/2) for implemented
scope and remaining acceptance. Independent F6 scenes
`tests/simulation/five_v_five_rules.tscn`, `tests/network/five_v_five_session.tscn`
and `tests/network/results_delivery.tscn` exercise 5v5 rules/spawns, ten real
clients and complete five-round result delivery. Network tests must run in real
time, without `--fixed-fps` acceleration.
Independent `tests/simulation/ffa_rules.tscn`, `tests/network/ffa_session.tscn`
and the FFA menu integration test cover rules, impaired sessions and app flow.
`tools/check-gameplay.ps1 -GodotPath <console executable>` runs the independent
natural duel: real drive/weapon commands, normal round rules, results and rematch.
It leaves production timers and combat state unchanged; allow up to its bounded
500-second match deadline. This is automated integration, not human feel approval.
Public deployment, durable identity/results and release polish remain future work.
Ten-player performance/soak is removed from active scope. Local automated tests do not
replace the two-computer LAN and human control-feel playtest.

Published Flamebot and sawblade art is included for inspection. The game still uses
primitive combat visuals. Flamebot has a validated runtime GLB; the sawblade folder
contains Blender source and is excluded from Godot import until its runtime export
is ready. Neither changes combat stats or collision in this checkpoint.
