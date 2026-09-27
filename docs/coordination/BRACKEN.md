# Bracken reference tank — issue #100

The first broad, boxy model was rejected by the user. This revision follows the
foreground reference with a narrower chassis, exposed diagonal suspension rams,
compact shielded gun cluster, dished track hubs, separate slatted flipper and
chipped olive/oxide-red paint. It is a separate factory preset; existing bots
retain their assets and rules.

[Editable source and portable model](../../art_source/bracken/README.md).
Runtime hull, turret and lifter GLBs live in
`battlebots/assets/models/bracken_runtime/`. Fourteen packed surface maps supply
base color, roughness/metallic/occlusion, normals and two enamel coverage masks.
Paint/hardware atlases are 2K; tracks are 1K. Godot imports generate LODs.
The complete assembly contains 198,240 base triangles including repeated track
shoes. The manifest also records atlas occupancy; these are inventory figures,
not a frame-time claim.

The large suspension rams attach to pinned clevises beside the rear sloping
plate. The smaller gun-elevation cylinders and rods aim at their actual moving
anchors without scaling the geometry or textures. Tracks, rollers, turret,
barrel recoil and ramp use the established runtime animation and combat paths.
Individual armor assemblies and ramp slats feed the generic part-loss/wreck
pipeline. All permanent painted/metal/rubber surfaces have baked texture maps;
the tiny painted insignia and sensor lens retain their authored materials.

## Validation of the revision, 27 September 2026

Final CPU bake, production import and all checks below passed.
[Recorded results](evidence/bracken-2026-09-27/validation.txt) and
[artifact hashes](evidence/bracken-2026-09-27/artifact-hashes.json) identify the
exported assets; the final saved source has fourteen packed images and zero
contacts in the sampled audit.

- `bracken_model_test.tscn`: imported geometry/materials, 104 moving shoes and
  ten wheels, muzzle/authority agreement, engaged coaxial hydraulic rods,
  narrower collision envelope, sealed preset, persistence and pickup compatibility.
- `bracken_physics.tscn`: real Jolt ground contact and forward driving, four
  authoritative cannon hits and damage, lifter charge/release, replicated aim.
- `destruction_models_test.tscn`: Bracken and every existing model retain
  component pools and saw/railgun/mortar splitting. Bracken exposes weapon,
  drive and six panel clusters; fragments retain the original textured materials.
- `baseline_smoke.gd`, `atlas_catalogue.gd`, `atlas_turret_physics.tscn`,
  `atlas_turret_visual_test.tscn`, and the complete stale-class-cache startup
  check pass. The latter includes its real headless menu-flow launch.
- Source BVH sweep checks 72 turret bearings at the published lower limit,
  neutral and +30 degrees. Track clearance covers all fixed hull and drive
  parts at the authored phase. Geometry corrections removed bearing overlap,
  guard/hinge-pin interference and ram-hose/track contact before final baking.
- Source hero/front/side/top renders are actual Blender output, not generated
  concept images. They document the revised asset. The earlier rejected
  version's evidence has been replaced.

The user explicitly requested **no game/editor launch after completion**.
Revision checks remain headless; no new native Practice capture is claimed.
Visual fidelity and control feel remain matters for the user's review, not
properties established by automated tests. The sampled clearance audit does
not cover every simultaneous transient lifter/turret pose.

## Compatibility and release

Build `mvp-ab-54`, catalogue 19, protocol 17. Bracken's physical width, bore
spacing and hydraulic anchors are in `data/bracken_geometry.json`, read by
`AtlasGeometry` and the Blender generator. Both hit authority and visible gun
muzzles use the narrower offsets. Existing revision-18 loadouts migrate with
their parts and cosmetics intact; stale peers still fail compatibility checks.
The new tests are registered with the simulation/presentation runners.

Integration and live deployment results are recorded on
[issue #100](https://github.com/fumbleforce/battlebots/issues/100).
