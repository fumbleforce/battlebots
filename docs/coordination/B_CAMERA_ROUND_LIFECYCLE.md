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
