# Worker B — shared task list

Worker B maintains this list after every increment. Worker A can use the IDs in
handoffs or PRs. Status describes B's branch, not what has been merged to main.
Nothing here implies A has already implemented a requested dependency.

**Current branch:** `codex/b-arena-camera` (camera baseline plus dependent UI work).
**Current increment:** B-02, reusable bot-status HUD.
**Integration reference:** [B handoff](DEVELOPER_B_HANDOFF.md).
**Working rules:** [ownership and workflow](TEAM_WORKFLOW.md).

## Done on B's branch

- [x] **B-01: Arena and third-person camera.** Floor, walls, chamfered corners,
  team/FFA spawns, camera collision, orbit/zoom/recenter, stable horizon, and mock
  camera test controls. Baseline and presentation tests passed. Ready for A to
  review wall collisions and camera feel with the real drive implementation.
- [x] **B-00: Visible cooperation plan.** This checklist records sequence, file
  ownership, completion criteria and dependency requests for A.

## Active and next — B can do these independently

- [ ] **B-02 — IN PROGRESS: Reusable status HUD.** Replace the diagnostic text
  with labelled core/battery/heat/weapon-charge bars and textual state. Consume
  existing BotView only. Handle missing targets and invalid/out-of-range display
  values without showing stale bot information. Keep the mock label obvious.
  **Done when:** the same UI works in A and B sandboxes, scene checks pass, and
  the rendered HUD is readable at 1280 × 720. B-owned UI/presentation files only.
- [ ] **B-03: Camera settings UI.** Sensitivity, Y inversion, automatic recenter,
  and recenter strength, with defaults and local persistence. Use a B-specific
  settings file until A's profile/settings service is agreed; do not introduce a
  competing global service. **Done when:** settings work live and survive restart,
  and opening the panel neutralizes gameplay input.
- [ ] **B-04: Input and menu polish.** Keyboard navigation, reliable cursor
  capture, focus-loss behavior, and clear resume/return controls. Prepare rebinding
  UI against an agreed settings adapter; ask A for required InputMap changes.
  **Done when:** menus cannot accidentally drive or fire the bot and can be used
  without a mouse. Full rebinding waits for agreement on persistence ownership.
- [ ] **B-05: Arena readability pass.** Team identifiers that do not rely solely
  on color, clearer bot facing, restrained materials/lighting and spawn inspection
  helpers. **Done when:** players can distinguish facing and teams at follow-camera
  distance; decorative objects add no combat collision.

## Next integration checkpoint — A + B

- [ ] **AB-01: Real drive + B camera/HUD.** A exposes the real bot via the current
  BotSource contract. B connects presentation without editing A's drive logic.
  Together check acceleration, reverse steering, wall contact, flipping, recovery,
  camera jitter and component feedback on both office computers.
  **Needs from A:** a branch/commit ready to test; stable camera anchor; complete
  camera_exclusions RIDs; coherent BotView snapshots. No new contract is required
  for the initial core/resource bars.

## Waiting for A's interfaces — do not guess authoritative state

- [ ] **B-06: Network/debug overlay.** Display connection state, RTT and correction
  metrics. **Needs A:** read-only diagnostic fields/signals with units and update
  semantics. Use explicitly labelled fixtures until those exist.
- [ ] **B-07: Lobby and ready flow.** Slot/team/build validity views plus host,
  join, ready, leave and failure messages. **Needs A:** session request API and
  lobby-view contract; server remains responsible for readiness and transitions.
- [ ] **B-08: Match HUD/results/spectating.** Timer, round score, survivors,
  elimination/recovery messages and results. **Needs A:** authoritative match view,
  event IDs and bot states; B never infers winners from local health displays.
- [ ] **B-09: Garage preview and build UI.** Socket selection, part comparison,
  validation errors, save/load and test-drive. **Needs A:** registry, legal-loadout
  validator, derived stats and persistence API. Art/preview mocks can proceed first.

## Later B scope

- [ ] **B-10:** Weapon animation/audio/VFX using A's weapon state and impact events.
- [ ] **B-11:** Tutorial, accessibility settings, controller presentation and final UI.
- [ ] **B-12:** Optional first-person camera after third-person integration is stable.

## Coordination and editing boundaries

B is actively editing `scenes/ui/`, `scripts/ui/`, `scripts/presentation/`, B's
sandbox, B's fixtures/tests and B-owned documentation. A owns simulation, networking,
bot assembly, shared contracts, data, app bootstrap and project.godot. Ask before
changing the other owner's files; propose contract changes in a handoff first.

After each completed increment: update this list and the handoff, run relevant
checks, commit task files only, fetch/rebase onto origin/main, and push the task
branch. Preserve unrelated local edits. Rebasing/pushing a feature branch does
not merge it to main; A and B should review integration changes before merging.

## Latest handoff to A

- B-01 is ready on this branch; B-02 is next and uses existing BotView fields.
- Continue drive/network work without editing B's UI/camera scenes.
- No engine settings or new input actions are requested for B-02.
- Please identify the real-drive integration commit when ready; joint playtesting
  remains outstanding. This checklist is a repository handoff, not a sent message.
