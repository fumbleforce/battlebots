# Scorpion shutdown texture investigation (#18)

[Task #18](https://github.com/fumbleforce/battlebots/issues/18), investigated on
23 September 2026 with official Godot **4.7.2.stable.ed1daf0bf**, Linux,
Vulkan Forward+, NVIDIA RTX 3080. No game assets, rendering quality, gameplay,
compatibility version or engine pin are changed by this investigation.

## Finding and resource owner

The seven shutdown Texture RID warnings originate in Godot's **reflection
atlas**, not Scorpion's imported model, procedural materials, particles or bot
assembly. The original native `scorpion_showcase.tscn` reproduces seven; an arena
with no bots also reproduces seven. Removing only the arena ReflectionProbe
before rendering eliminates them, including with a live Scorpion loadout swap.
The isolated model, assembled visual and full bot exit without RID leaks.

An empty project containing a camera and ReflectionProbe reproduces the same
warning without any Battlebots scripts, assets or autoloads. This matches
[Godot issue #122498](https://github.com/godotengine/godot/issues/122498).
Inspection of the exact pinned engine revision confirms that
[`LightStorage::_reflection_atlas_clear`](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/storage_rd/light_storage.cpp#L1558)
does not release the color cubemap and six shared color views allocated by
[`reflection_probe_instance_begin_render`](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/storage_rd/light_storage.cpp#L1765).
Those are the seven Texture RIDs. The same cleanup also omits their framebuffers;
the warning specifically counts texture handles, not seven independent images.

## Measured limit and remaining engine defect

Ten repeated builds/frees, and ten real `AuthorityWorld.apply_loadout` bot
replacements in each full-world case, check node destruction through weak
references. Texture memory and resource counts plateau after the first cycle; global helper
object counts settle later and are checked across the final third of cycles.
Foundry arena reconstruction in the same root World3D still reports only seven
texture handles when the process exits, rather than seven per bot or probe.

The empty-project controls distinguish world reuse from world destruction:

| Ten-cycle case | Texture RIDs at exit | Texture growth per later cycle |
| --- | ---: | ---: |
| New viewport/world, no probe | 0 | 0 bytes |
| New probes/viewports sharing one World3D | 7 | 0 bytes |
| New own World3D with a probe each cycle | 70 | 3,145,728 bytes (3 MiB) |

The accumulating leak is therefore **per destroyed reflection atlas**, not per
Scorpion or necessarily per probe. At the tested default 256-pixel cubemap size,
its color storage is 6 × 256 × 256 × 8 bytes; shared views do not each duplicate
that storage. Larger atlas sizes can leak more. Do not describe repeated
independent-world creation as bounded or leak-free.

Current session reconnect/leave/rebuild creates ordinary `AuthorityWorld`
Node3Ds under the existing viewport, retaining its World3D. Garage previews own
separate worlds but contain no ReflectionProbe. All production probe creation
sites are in Foundry, Moon and Woodland arena presentation. The measured plateau
applies to the tested same-world Foundry path; it is not a measurement of every
arena, graphics setting, platform or rendering backend. The much larger retained
reflection-atlas cache during a live shared world is separate from the 3 MiB
left behind after an atlas is destroyed.

Keep the upstream engine issue as the fix dependency. Do not disable arena
reflections or change the pinned engine solely to hide this diagnostic. Re-run
these controls when upgrading Godot or introducing probes into disposable
preview worlds; update expected known-leak counts when the engine fix lands.

## Reproduction and retained evidence

Run from the repository root with a desktop display/GPU available:

```sh
node tools/check-scorpion-lifecycle.mjs --godot /path/to/godot --output /tmp/scorpion-lifecycle
```

The runner imports the project, verifies the 4.7.2 pin, then serially runs six
native game controls and three empty-project controls for ten cycles each. It
retains complete logs and JSON memory samples, checks node destruction, exact
shutdown RID counts, post-warmup texture deltas, resource/object plateaus, process
exit and script/native crash diagnostics. The known upstream warning is reported
explicitly; other RID/ObjectDB leaks fail the check. Headless rendering cannot
establish this diagnosis and is rejected by the fixtures. Baseline remains a
separate required check.

The standalone `reflection_atlas_repro.gd` can be copied into any empty Forward+
project, independently of this repository. `--replace-world` selects separate
World3Ds; `--no-probe` removes probes; `--cycles=N` controls repetition.

[Retained report](evidence/scorpion-lifecycle/report.json) contains all final
samples and renderer identity. [Native log excerpts](evidence/scorpion-lifecycle/native.log)
retain the original failure and final shutdown counts. This completes #18's
explicit verified-engine-issue investigation outcome; it does **not** claim
that Godot's leak has been fixed. A hosted release is not needed for these
standalone tests and documentation.
