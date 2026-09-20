# Camera/input round lifecycle — B intent

Branch `codex/b-camera-round-lifecycle`, from main `bd0af46`.
B is checking the camera and input adapter across elimination, next-round reset
and replacement of the current session bot. Existing initial-binding and deleted
fixture checks do not directly cover these transitions.

Add an independent scene using real sessions and the existing presentation
adapter/menu composition. Assert current anchor/exclusions, finite constrained
camera, neutral eliminated/transition input, and release-before-rearm on return.
No new spectator feature: team/FFA cycling stays deferred behind the 1v1 priority.

Reserve only the new B presentation fixture, test-runner registration and docs.
If a production defect appears, reproduce and coordinate the owner before fixing.
The concurrent Sawblade task retains models, drive, weapons and customization;
A retains session lifecycle and general menu implementation.

## Paused checkpoint — user requested wrap-up

Rebased onto main `7ce48ab`, preserving both teams' coordination entries.
The new camera_round_lifecycle scene covers real composed practice knockout,
restart and full leave/recreate. Actual app gates and held action input verify
cancellation/release-before-rearm; current anchor/exclusions and finite bounded
camera checks pass. Headless verbose run exits 0 without leak warnings.
It does not yet exercise a network duel's intermission/next-round transition.
Keep this unfinished acceptance work on the task branch; do not merge it as
completed duel-lifecycle coverage. No production files changed.

During main import/baseline validation, BASELINE PASS printed but the process
exited -1073741819 (access violation). The runner correctly rejected that result;
the shutdown failure remains unresolved and has been reported to the other task.
The latest main game was launched separately for user testing.
