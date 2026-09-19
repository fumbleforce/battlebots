# Project Battlebots

Godot **4.7.2 stable** / Jolt / typed GDScript. Two developers, one repository, separate local clones.

## Start
1. Clone the repository locally and install Godot 4.7.2 stable.
2. Import `battlebots/project.godot` into Godot.
3. Press **F5** for the game menu; choose Practice or Multiplayer.
4. Press Escape in the arena for build selection, camera settings and session controls.

The integration branch combines A's combat/networking with B's arena, orbit camera,
resource HUD and camera settings. Simple spinner and lifter geometry shows weapon
charge/activation; these cosmetic meshes add no collision. The centered session
menu offers Striker/Controller, practice reset, host/join, ready and rematch. B's
full garage and production match screens remain future work. Development sandboxes
are still available by opening their scenes and pressing F6.

## Work independently
- **A:** `battlebots/scenes/dev/a_simulation.tscn` — drive controller, then networking.
- **B:** `battlebots/scenes/dev/b_presentation.tscn` — implement arena/camera/UI using the mock.
- Read [handoff](docs/HANDOFF.md), [contracts](docs/CONTRACTS.md),
  [team workflow](docs/TEAM_WORKFLOW.md), and [full specification](docs/GAME_SPEC.md).
- Agree who is A/B, then branch from the common baseline:
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
For manual inspection, use F5 and both launcher buttons; Escape opens the session
menu. Use the explicit Main menu action to leave the session and return to the launcher.
Public hosting is a later release task; MVP export presets are described below.

## Playable modes

Current A branch: `codex/a-ffa`, build `mvp-ab-5`, protocol 4.
Use the same branch/build on all peers. The older `codex/a-b-integration`
checkpoint remains available; it does not include the 5v5/FFA follow-ups.

The main menu offers **Practice** and **Multiplayer**. Multiplayer opens session
controls without starting practice. WASD/Space drive/brake, LMB powers the spinner or raises
the lifter (release fully charged to flip), RMB brakes/lowers, and R self-rights
when eligible. Select Striker/Controller, then Practice/reset to test either build.
The spinner disc rotates with charge; lifter forks rise and flip from weapon state.
Escape releases controls and opens the menu; Resume recaptures the mouse.

Use Godot 4.7.2 from the repository root (replace `$GodotPath` with your executable):

```powershell
& $GodotPath --headless --path battlebots -- --server --players=2 --port=24567
& $GodotPath --path battlebots -- --join=127.0.0.1 --port=24567 --ready
& $GodotPath --path battlebots -- --host --players=2 --port=24567
& $GodotPath --path battlebots -- --host --mode=ffa --players=8 --port=24567
& $GodotPath --path battlebots -- --practice --controller
./tools/check-mvp.ps1 -GodotPath $GodotPath
./tools/check-processes.ps1 -GodotPath $GodotPath
./tools/check-processes.ps1 -GodotPath $GodotPath -PlayerCount 10
./tools/check-processes.ps1 -GodotPath $GodotPath -Mode ffa
```

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
Open one game window on each computer. On PC A choose Multiplayer, keep
**2 players / 1v1**, then click **Host game**. On PC B enter PC A's Ethernet/Wi-Fi
IPv4 address shown in the lobby (for example `192.168.1.20`) and click **Join game**.
Choose builds and press **Ready** on both PCs to start the countdown.
Choose **4 players / 2v2** when four people are available, or **10 players / 5v5**
when ten people are available. Each person needs only one game window.
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
