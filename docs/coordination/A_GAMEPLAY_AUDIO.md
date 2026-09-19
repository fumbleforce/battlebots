# A gameplay audio increment

Owner: A. Branch `codex/a-gameplay-audio`, based on merged `ad1607d`.
Current division: A owns audio/general menus; B combat/bots/customisation/controls.
Use authoritative combat events and read-only match/bot views. Do not change B
mechanics, control production, bot assets or the supplied menu melody.

First increment: distinct original procedural impact cues, countdown/start/end
announcements with visual captions, local warning/recovery cues, bounded voices,
and independent Music/Effects/Announcements buses with saved volume/mute controls.
Remaining drive/skid/spin layers and final authored sound design stay explicit
follow-up work. No full audio acceptance claim from this increment alone.

Parallel ownership: audio agent owns sound bank/controller and isolated tests;
settings agent owns audio preferences/buses, standalone panel and isolated tests;
root owns menu-shell composition, integration checks and docs. No overlap with
B's control settings implementation: compose a separate Audio panel in the shell.

Complete each validated increment by local merge into main and direct push; no PRs.

Implemented: five distinct impact types (both spinners share the spinner cue),
three-second countdown, fight/round/results tones and captions, local low-core
hysteresis and recovery activation. Four effect voices/two announcement voices
are reused; bounded event history rejects duplicate/stale events. Re-entering
practice correctly restarts its event IDs. These are non-spatial first-pass cues,
not spoken announcements or final authored sound design.

Settings: master, music, effects, announcements and mute persist to versioned
user://audio.cfg with finite range validation and temporary-file replacement.
Preview, cancel restoration and save failures are explicit. The supplied melody
now uses BBMusic. Settings → Audio works both from the main menu and in a match;
Escape returns to Settings, and gameplay input stays disabled during the modal.

Godot 4.7.2 focused GAMEPLAY AUDIO, AUDIO SETTINGS and AUDIO MENU checks passed
with exit zero and no warnings. Baseline passed. MENU FLOW passed with its known
two-object shutdown warning; this increment does not claim that issue fixed.
The audio checks are registered in the presentation runner. Human listening,
rendered visual acceptance and an updated packaged export remain unverified.

MENU MUSIC also passed, with three MP3 playback objects reported at shutdown.
One verbose diagnostic identified AudioStreamMP3 and two AudioStreamPlaybackMP3
references, not the new PCM cue bank. That shutdown issue remains unresolved.

The real-time two-peer MENU GAME NETWORK check passed cleanly through countdown,
two rounds, results and rematch, including exact transition-cue counts. Its first
run found that a global announcement throttle suppressed results immediately
after Fight; phase cues now preempt a bounded voice instead. A same-frame
transition regression also passes. An intermediate invocation omitted the required
--max-fps 60 and exhausted frame-based deadlines; it is not acceptance evidence.
Final logs: %TEMP%/battlebots-gameplay-audio.log and
%TEMP%/battlebots-audio-network-test.log. No native crash occurred in these runs;
the pre-existing intermittent engine shutdown issue is not claimed resolved.
