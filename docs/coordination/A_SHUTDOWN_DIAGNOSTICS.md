# A — Windows shutdown diagnosis

Intent 2026-09-20, `codex/a-shutdown-diagnostics`, base `7287540`.
A reserves independent shutdown diagnostics and validation harnesses. Reproduce
the native Windows `0xC0000005` failure before proposing a runtime fix. Existing
evidence places the crash in GDScript language teardown after passing gameplay
assertions; extra scene-cleanup frames were already ineffective.

Use bounded diagnostic repetitions with every outcome retained; these are not
retries that turn a failed gate green. Compare minimal isolated scripts/projects
against the real project's autoloads to identify the smallest useful reproducer.
Read-only dependency audit runs independently. No B controls, bots, combat or
camera implementation edits without a documented ownership handoff. Preserve
Godot4.7.2/Jolt and all existing failure gates.

Local bounded diagnosis: isolated empty scripts passed 12/12 exits, project
autoload empty scripts passed 12/12, baseline fixtures passed 8/8, and drive
fixtures crashed 2/8 after DRIVE PASS. Windows reported exception 0xc0000005
at fault offset 0x547f2c. Removing WireCodec's concrete MvpBot parameter type
experimentally still crashed 4/24 drive exits, all after DRIVE PASS. That
experiment was reverted; the dependency-cycle hypothesis does not provide a
validated fix. Logs remain in the local temporary diagnostic directory
`battlebots-shutdown-924d30f1ee354f4594e9da738190bd74`. No gate is claimed green.

## Repeatable diagnosis and gate validation

Run `tools/diagnose-shutdown.ps1 -GodotPath <4.7.2-console-executable>` for eight
drive trials; `-Fixture baseline` selects the independent baseline and `-Trials`
accepts 1 through 50. Each trial records its exit, completion marker, native/script
errors and elapsed time. The temporary report includes source revision, dirty
state and engine version and is rewritten after each exit. Any failed trial
fails the entire invocation, even if later trials pass. These are diagnostic
repetitions, not retries in CI. Eight drive trials with the committed runtime
unchanged were clean locally; that sample does not erase earlier failures.

The production `check-drive.ps1` now rejects native exception/crash/backtrace
signatures as the existing baseline gate already does. Its independent fake-engine
regression covers 23 cases, including false exit-zero/PASS combinations and
nested import/baseline failures. The real pinned-engine import, baseline and
drive checks also passed locally once. No full Windows CI success or runtime
crash fix is claimed.

Load-only, instantiate/free off-tree and short on-tree physics/free experiments
were each clean 10/10. Repeated replacement of 12 bots was clean 12/12. A single
bot processing commands and reading views over 2,000 frames crashed 1/12 after
its completion marker, with exit -1073741819 and no native text. Repeated bot
replacement is therefore unnecessary to reproduce the failure. This smaller
case still uses the real public BotSource API and pinned Jolt physics.

Splitting that workload reproduced both paths independently: commands-only
crashed 1/12 with native backtrace despite exit zero; views-only crashed 1/12
with exit -1073741819. Windows events match fault offset 0x547f2c. Commands and
repeated replacement are therefore not required; the underlying cause is still
unproven. Temporary scripts, exact logs and split-report.json are in
`battlebots-shutdown-lifecycle-fb7f8dc4e1c04ad0be633ada3cc9b9a6`.

`-Fixture views` runs the preserved small A integration workload in
`tests/networking/shutdown_view_diagnostic.gd`: one bot, ground and 2,000 public
view reads/physics frames, then normal teardown. Its simplified repository
version was clean in 12/12 trials; do not describe it as deterministic or as
having fixed the original temporary reproduction. It is opt-in diagnosis, not
an additional flaky CI gate. The runner's six fake-engine regression cases
verify retained raw logs and that a failed first trial still fails after a clean
second trial, including native text with exit zero and native exits without text.

Later observation: Windows [run35502338810](https://github.com/fumbleforce/battlebots/actions/runs/35502338810)
at35ef6a6 passed the full workflow, including the new gate regressions and exports.
This supersedes the earlier lack of a green run for that checkpoint; it does not
invalidate the retained intermittent failures or establish a runtime fix.
