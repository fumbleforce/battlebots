# B results follow-up

Owner: B. Branch: `codex/b-results-followup`. Base: `3f0e80f`
(`origin/codex/a-performance`), including the published B menu kit and art.
The original main checkout and its pre-existing project.godot edit are untouched.

The default B menu shell now opens a reusable results panel automatically. It
consumes detached session results, shows aggregate/per-round participant counters,
labels authoritative FFA places/shared winners, and distinguishes missing values
from zero. Stale/duplicate records are rejected. Rematch sends one phase-gated
request and says it is waiting; it does not claim server vote acknowledgement.
Server transitions clear the panel; explicit Leave returns to the main menu.

No shared API, physics, networking, bot assembly or project settings changed.
This increment integrates the default menu shell; the older standalone lobby
fixture keeps its existing UI. Spectator cycling, team/build names in result rows,
and broader accessibility/presentation polish remain future B work.

Validation: Godot 4.7.2 baseline and independent results checks pass, including
malformed/stale data, FFA shared placement, ten participants, per-round values,
detached records and vote state reset. Rendered 1280x720 results inspected.
The real two-peer menu integration check covers full match and rematch; its final
outcome is recorded in the B handoff. Human two-computer LAN remains unverified.
