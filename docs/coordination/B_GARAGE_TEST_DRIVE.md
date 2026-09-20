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
input release and 720p/1080p/ultrawide150% integration checks. Pin Godot4.7.2.
