# Unsaved-build test drive — Developer B

Branch codex/b-garage-test-drive, from shared main e0ce7c4. The spec requires a
Test Drive action that opens practice with the unsaved draft. B owns the entry
and draft preservation; A owns practice/session and general navigation.

Implement a separate GarageTestDriveEntry installed by menu_game for Garage and
Customize, reusing existing MvpSession.practice and the selected arena. Test Drive
must not save or reload the profile, discard undo history, replace invalid parts,
or leave an existing online session. Return and restart preserve the draft and
originating build screen. Main-menu Practice keeps its existing return behavior.

Allowed paths: new B entry/test scenes, menu_game integration and documentation.
Do not edit Customize, PlayerProfile, registry, bot art or drive scripts while
codex/b-sawblade-integration is active on that ownership slice. Intent was also
sent to the active Sawblade task; it owns authored modules and walking locomotion.

Acceptance: independent entry layout/input/validation; real practice consumes
unsaved parts/name/paint and returns without disk writes or history loss; invalid,
active-session and modal entry guards; normal Practice remains unchanged; restart,
input release and 720p/1080p/ultrawide150% integration checks. Pin Godot 4.7.2.

## Delivered and verified

GarageTestDriveEntry installs into the existing footer without modifying either
workshop's source. It caches detached draft validation, guards direct activation
and uses the full shared text factor. menu_game's optional practice origin records
Garage/Customize only after successful admission. The ordinary no-argument
practice entry keeps its original Main return. No profile/save/model/drive edits.

The independent real-game scene seeds a temporary save, edits name/weapon/paint,
starts practice from both screens and verifies the admitted bot's exact draft.
Restart retains its identity/build; Return preserves draft and undo history and
leaves saved bytes unchanged. It rejects recovery/settings and active-session
entry, validates invalid-build disabling, and checks settings opened during a test
return to Pause with BACK TO BUILD intact. Actual Ctrl+Z and unbound Escape input
prove hidden workshops cannot mutate history or navigate behind gameplay. Return
recreates a processing-enabled build screen. Main Practice still returns to Main.

Pinned Godot 4.7.2: GARAGE TEST DRIVE ENTRY and GARAGE TEST DRIVE GAME pass.
Native D3D12 entry layouts pass 720p/1080p/ultrawide at 100/150%; actual composed
Garage/Customize and pause-return screenshots were inspected at 720p. BASELINE,
PRACTICE MENU, MENU FLOW and real UDP MENU KIT LOBBY pass. New independent scenes
are registered in check-presentation.ps1. No new remote-play or combat-feel
acceptance is claimed. The concurrent Sawblade/physical-legs integration remains
separate until its owner completes validation and merges it.

Reproduce native composition with garage_test_drive_game_test.tscn -- --capture;
images are written to the local TEMP directory as test-drive-game-*.png.
