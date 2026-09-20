# Manual hosted playtest — menu correction intent

User feedback, 2026-09-20. Current A branch: `codex/a-live-duel-refinement`.
The released Fly-compatible client exposed oversized scrolling navigation,
grey margins, two yellow primary actions, mismatched settings without video
options, an easily missed private code, and weak vehicle selection/showcase.
All seven requests are tracked on A_MVP_TASKS.md; its current checkboxes distinguish
implemented corrections from remaining acceptance. This feedback supersedes
previous claims that automated layout checks establish finished menu presentation.

A is implementing responsive general navigation, full-bleed background, softer
secondary button states and a persistent lobby code/copy action first. A also
owns the new themed settings hub and video preferences. Existing camera and
control behavior remains B-owned; agree integration before changing those panels.

B owns the prominent vehicle selection/switching UI and real assembled-bot
preview on a rotating pedestal. A requests a reusable component/API for general
main and lobby integration, including selection changes and ready/loadout locking.
Avoid parallel edits to B's garage, profile persistence, assembly or input code.

Validate independent scenes and actual resized windows at 1280x720, 1920x1080
and ultrawide, default and enlarged text, keyboard and mouse. Main/navigation
menus must not require scrolling; the background must cover both axes. Verify
private room code survives the creation-to-lobby transition and Copy copies the
public code only. Keep live Fly deployment stable while the user playtests.

Existing uncommitted scoreboard, result wording and hosted reconnect work is
preserved. Do not describe this feedback as resolved until implementation and
rendered checks pass; human acceptance remains open.

## Implemented correction evidence

The main menu removes its ScrollContainer and compacts the wordmark/action rows.
Only Play Online uses the yellow primary style; LAN uses subdued hover styling.
Independent headless and native checks pass at 720p, 1080p, ultrawide and 1280x1024,
through 150% text. A composed-game check also verifies that the actual host and
background cover the complete viewport on both axes, rather than only testing a
replica of the layout calculations.

The private lobby keeps the eight-character public friend code and Copy code
action in its header after connection. Independent rendered checks pass at 720p
through 150% text, and a native clipboard check verifies the actual copied value.
Quick Play/direct sessions do not display private sharing controls.

The new themed settings hub separates Video, Audio, Accessibility, Camera and
Controls. Video provides windowed/borderless/fullscreen, windowed resolution and
V-Sync, with a 15-second Keep/Revert transaction. Separate physical-state capture
preserves window position, size, mode, borderless flag and V-Sync for rollback.
Headless adapter tests prove persistence/rollback; native render-only checks
prove 720p layout at 100/150%, including confirmation. These do not prove physical
display-mode switching on the user's monitor. B's subsequent `9e54dcc` adds
grouped no-scroll Controls and responsive Camera presentation through this hub.

B published GarageBotPreview in `682824b`, providing a validated isolated 3D build
preview in Garage/Customize. The subsequent featured-vehicle branch consumes it
in main/lobby with Previous/Next and optional pedestal rotation. Its coordinated
consumer changes preserve host-confirmed Apply and existing selection locks. See
[B implementation/evidence](B_FEATURED_VEHICLE.md); final authored art and human
presentation acceptance remain separate from this canonical primitive preview.

Full presentation runner passes, including real networked lobby/reconnect,
private/Quick Play client flows and the held scoreboard during live driving,
pause, authoritative results and rematch. The first combined run exposed old
fixtures closing the former camera-only settings entry; those now exercise the
new hub's Back action and the full runner passes. Existing ObjectDB cleanup
warnings remain; no native crash occurred in this validation.

Rebased onto B's shared main through `e24ab02`, retaining live garage preview,
part comparisons and saved-build repair. Post-rebase baseline and ten affected
garage/profile/main-menu/settings checks pass. No wire/content identity changed;
the existing Fly worker remains compatible and was not redeployed.

A second fetch integrated B's `d6e154e` save recovery. The shared coordination
note conflict retains both developers' entries. Baseline, both new recovery
scenes and affected customization/menu-kit/actual host-fit checks pass.
