# Two-developer workflow — Project Battlebots

This project is developed by two people on separate computers in the same office, both using ChatGPT, in one shared Git repository. This document defines proposed ownership and coordination; it does not create branches, assign accounts, or start additional ChatGPT tasks.

Developer A and Developer B are role labels. Either person can take either role. Agree the mapping once before implementation and keep it stable through the first playable 2v2 match.

## 1. Ownership

The shared baseline is now implemented. Start with [HANDOFF.md](HANDOFF.md) and
[CONTRACTS.md](CONTRACTS.md); use the existing typed adapters and sandbox scenes
instead of recreating the foundation described in the original starter prompts below.

**Developer A owns simulation and multiplayer.** Physics and networking stay together because contact response, prediction, weapon hits, and authoritative state are tightly coupled.

**Developer B owns the player experience and content.** Camera, input collection, arena presentation, garage, HUD, and assets can progress using agreed contracts and mock data while simulation is being built.

| Area / proposed path | Owner | Boundary |
|---|---|---|
| `battlebots/scripts/simulation/` | A | Drive forces, damage, battery, heat, recovery, authoritative match rules |
| `battlebots/scripts/weapons/` | A | Weapon state and hit detection; B supplies visuals |
| `battlebots/scripts/networking/` | A | ENet sessions, input validation, replication, prediction, reconnect |
| `battlebots/scripts/core/` | A | Shared record definitions, registry, IDs, protocol versions |
| `battlebots/scripts/services/` | A | Session, lobby backend, identity, allocation, verified results |
| `battlebots/scenes/bots/` | A | Bot assembly, physics hierarchy, collision and damage zones |
| `battlebots/scripts/presentation/` | B | Camera, local input adapter, animation, audio, VFX |
| `battlebots/scenes/arenas/` | B | Arena assembly and spawn markers; collision changes reviewed by A |
| `battlebots/scenes/ui/`, `battlebots/scripts/ui/` | B | Menus, garage, lobby UI, HUD, results, settings |
| `battlebots/scenes/practice/` | B | Tutorial flow and practice presentation; uses A's simulation API |
| `battlebots/assets/` | B | Models, materials, textures, audio, effects, presentation-only subscenes |
| `battlebots/data/` | A | Canonical part stats and validation; B requests asset-reference updates |
| `battlebots/scenes/app/`, `battlebots/project.godot` | A | Bootstrap, autoloads, input actions, main scene, engine settings |
| `battlebots/export_presets.cfg`, CI configuration | A | Client/server export and automated builds; no committed credentials |
| `battlebots/tests/` | Both, by subfolder | A: simulation/network; B: UI/presentation and content validation fixtures |
| `docs/GAME_SPEC.md` and shared contract docs | Both, one editor per change | Agree intended change in the issue/PR before modifying shared rules |

Ownership means responsibility and a default editing boundary, not exclusive knowledge. Cross-owner changes are normal when agreed explicitly. Do not edit the same `.tscn`, `.tres`, `.godot`, or binary asset simultaneously. B provides weapon presentation scenes under `assets/`; A mounts them in the bot scene. B provides HUD scenes; A instantiates them from the app scene.

## 2. Repository and branch workflow

1. Keep **one remote repository and one separate local clone on each computer**. Do not put the working checkout or `.godot` cache on a shared network drive or synchronize them through a file-sync service.
2. Keep `main` runnable. Both computers use the same Godot 4.7.2 build and matching export templates. Commit source assets, `.uid` files, and required `.import` configuration; exclude generated `.godot/` cache, temporary exports, secrets, and editor-local state.
3. Start each bounded task from current `main` on a branch such as `codex/a-drive-controller` or `codex/b-camera-rig`. Prefix labels are examples, not existing branches. Do not have both developers push to one feature branch.
4. Before asking ChatGPT to implement a task, record owner, branch, allowed paths, acceptance criteria, and dependencies in the issue or task description. Tell ChatGPT to read this workflow and the game specification.
5. Keep changes small enough to review and integrate regularly. Each PR states what changed, how it was tested, any shared interface changes, and any migration needed. The other developer reviews shared contracts and scenes.
6. Merge dependency PRs before their consumers where practical. A branch depending on unmerged work states its base explicitly. Refresh against `main` before final verification; test the combined result on both computers for network-facing work.
7. Resolve scene conflicts with the scene's owner. Inspect the merged result in Godot; textual conflict resolution alone does not prove a scene still works. Never resolve by blindly taking one entire side.
8. After a merge, both developers fetch the updated baseline before starting dependent work. Commit work before changing tasks; never overwrite the other person's edits or force-push a shared integration branch.

Use Git LFS for large source art/audio if the remote supports it and both machines have it installed; agree this before adding large binaries. Small Godot scene/resource files remain normal text in Git.

## 3. Shared interfaces agreed before parallel implementation

A drafts the shared contracts in the first foundation PR; B reviews them against camera, garage, and HUD needs. Commit the actual typed definitions under `scripts/core/` and a short usage example. The following are required responsibilities, not a claim that these APIs already exist.

| Contract | Producer → consumer | Agreement |
|---|---|---|
| Input command | B's input adapter → A's simulation/session | Normalized throttle/steer, brake, explicit action flags, input sequence; mouse orbit stays local |
| Read-only bot view | A's state adapter → B's HUD and visuals | Entity ID, smoothed presentation pose, facing, health zones, resource percentages, weapon state, recovery eligibility, elimination state |
| Camera target | A's bot presentation anchor → B's camera | Stable node/handle, forward direction, local collision exclusions; B never writes authoritative transform |
| Loadout draft and validation | B's garage ↔ A's registry/validator | Part IDs and cosmetics in; valid/invalid plus specific reasons and derived stats out |
| Session request | B's lobby UI → A's service | Host/join/leave/ready calls with explicit success/failure events; UI never advances match state itself |
| Match view/events | A's match controller → B's UI/audio | Round index, timer, scores, team/slot list, match phase, results; events carry entity/round/event IDs |
| Weapon presentation | A's weapon state → B's effect scene | Charge, activation phase, impact location/normal, disable state; effect scene cannot award damage |
| Arena manifest | B's arena → A's match setup | Floor bounds, mode-specific spawn transforms, collision layers, arena ID; server must load collision without rendering dependencies |

Additional conventions to lock in that PR: meters and kilograms; Godot Y-up and −Z forward; degrees only in UI and radians in simulation; stable part/entity IDs; collision-layer names; action names; signal payload types; and which objects exist on a headless server.

B builds against local mock adapters implementing the same contracts. Put mocks in clearly named development fixtures; never make mock state the authoritative runtime implementation. A supplies a minimal functional bot scene early. Contract changes must update producer, mock, and consumer in one coordinated change or retain a temporary compatibility adapter.

## 4. Parallel delivery assignments

| Phase | Developer A | Developer B | Integration checkpoint |
|---|---|---|---|
| 0: Foundation | Contracts, bootstrap, input actions, rigid-body bot and ground contact | Graybox 50 × 50 arena, spawn markers, camera rig and input adapter | Drive a real bot through B's arena using B's input and camera |
| 1: Network spike | Two-peer server authority, drive prediction, spinner hit rules, snapshot state | Connection/debug UI, latency/correction overlay, spinner visuals and damage feedback | Each office computer drives a different bot; test remote contact and flips |
| 2: 2v2 slice | Four-player match state, lifter, elimination, judging, reconnect | Lobby, combat HUD, score/results flow, spectator camera, combat audio | Complete a full four-client match and rematch |
| 3: Builder MVP | Part catalogue/validation, bot assembly, save schema/migrations | Garage editing, preview, stat comparisons, loadout browser and practice UI | Saved legal builds produce identical server and garage stats |
| 4: Full content | 5v5/FFA rules, hammer/saw/horizontal-spinner mechanics, server optimization | Remaining models/effects, final arena, first-person camera, controller input | Ten-client stress match plus FFA with correct results |
| 5: Release | Backend allocation/auth/results, deployment, authority checks | Tutorial, accessibility, cosmetic presentation, final UX and asset optimization | External remote playtest and release acceptance checklist |

Neither person should wait for the entire other subsystem. B can use mock bot views for UI; A can use simple cubes and scripted input for simulation. Integrate at each checkpoint instead of merging two large independently built games at the end.

## 5. First task for each ChatGPT session

### Developer A: foundation and interface contract

> Read docs/GAME_SPEC.md and docs/TEAM_WORKFLOW.md. I am Developer A, responsible for simulation and networking. First inspect the existing repository and current branch. Implement the minimal shared typed contracts, application bootstrap, configured input actions, and one rigid-body driveable bot for Godot 4.7.2. Own scripts/core, scripts/simulation, scenes/app, scenes/bots, and project.godot. Publish the exact camera, input, and bot-view interface before B integrates. Keep the bot visuals primitive. Validate that the simulation can run without presentation on a headless server. Do not modify B-owned arena, UI, or presentation files without coordination. Report changed interfaces and the next integration step.

### Developer B: arena and camera against the contract

> Read docs/GAME_SPEC.md and docs/TEAM_WORKFLOW.md. I am Developer B, responsible for presentation and content. First inspect the existing repository and current branch. Build the graybox 50 × 50-meter arena, mode-specific spawn markers, third-person mouse camera, and input adapter for Godot 4.7.2. Own scenes/arenas, scripts/presentation, assets, and an isolated development test scene. Read A's shared contracts when available; until then keep placeholder dependencies behind a mock adapter and document assumptions. Do not edit project.godot, shared contracts, physics, or bot assembly. Supply the action names/settings required from A. Validate camera wall collision and horizon stabilization, then report how A should connect the scene.

These prompts are templates for the two existing development sessions. They do not authorize one session to create another task or modify the other computer automatically.

## 6. Office multiplayer testing

Use a stable agreed port, initially UDP 24567, with one computer hosting and the other joining its LAN IPv4 address. Make any needed local firewall allowance specific to the game/server executable and test network profile. A successful localhost test alone is not sufficient. Office LAN testing does not need public internet port forwarding.

For four-player testing, run two clients on each computer and one headless server on the stronger machine. For ten-player load testing, split clients across both computers and use scripted input clients where needed; those clients stress simulation/networking but do not replace human usability tests. Record client/server CPU contention so a busy development machine is not mistaken for a networking defect. Later repeat on a separate hosted server to validate deployment and real internet behavior.

Test both host directions during the listen-server phase. Record engine/build/content version, machine roles, RTT, loss/jitter settings, reproduction steps, and expected/actual behavior. Add emulated latency/loss using a repeatable test harness; a fast office LAN will otherwise hide correction problems.

At the end of a work session, leave a short handoff in the issue or PR:

```text
Owner / branch / base commit:
Completed:
Changed shared contracts:
Validation performed:
Known failures or blockers:
Files the other developer should avoid until merge:
Next integration action:
```

ChatGPT sessions do not automatically share conversation memory. The repository, issue/PR, contracts, and handoff are the common source of truth. Each session must inspect current files and Git status rather than assume the other developer's work is present.
