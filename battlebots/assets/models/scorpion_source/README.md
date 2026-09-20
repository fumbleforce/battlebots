# Modular Scorpion source

Original Blender hard-surface asset rebuilt against the user's six-view Scorpion
reference. The main generator authors the tapered chassis and radial leg parts;
separate tail and minigun modules author their mechanical assemblies. All geometry
is editable in Blender 5.2.1 LTS. The `.gdignore` keeps source and studio renders
out of Godot; portable GLBs and shared PBR PNGs live in `../scorpion_runtime/`.

## Rebuild and inspection

From the repository root:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/build-scorpion.py
```

The generator loads `tools/scorpion_tail.py` and `tools/scorpion_gun.py` through
their `build(namespace)` functions. Pass `-- --no-render` to skip rendering.
`scorpion.blend` includes the complete six-legged assembly, hidden unposed leg
prototypes, packed materials, studio lights and beauty camera. The beauty, front,
left and top PNGs are actual Cycles renders of the same exported geometry on a
light gray floor; arena lighting is provided by the game.

## Geometry contract

- Authoring coordinates are Godot metres, Y up, -Z forward. Runtime applies
  `BotScale` exactly once for the 1.6 x 0.5 x 2.0 canonical source envelope.
  Godot rigid-body transforms remain unit scale.
- Chassis footprint (X,Z): (-.40,-.82),(.40,-.82),(.80,0),(.40,.82),
  (-.40,.82),(-.80,0). Three rings define the shared physical silhouette:
  Y -.25 at scale .92, Y -.16 at scale 1, and Y +.25 at scale .70. Separately
  rounded, sloping trapezoid armor panels leave dark seams over that monocoque.
  Roof equipment and the recessed underframe are cosmetic.
- The compact diesel engine has a shallow vented service cover, filler cap,
  two swept open exhaust pipes, perforated wraparound heat shields and soot-dark
  rolled lips. `Scorpion/Body/ExhaustLeft` is (-.39,.66,.60), and
  `Scorpion/Body/ExhaustRight` is (.39,.66,.60). Their local +Y emission axes
  point along (-.20,.60,.7745966692) and (.20,.60,.7745966692), respectively.
  These source-space marker centers match the open outlet planes; the pipe bore
  radius is .046, narrowed to .045 at the lip. Runtime plumes consume the named
  transforms and apply model scale once. Exhaust equipment is visual only.
- The main hierarchy is `Scorpion/Body`,
  `Scorpion/TailBase/TailUpper/TailFore/TailExtension/HammerHead`, and
  `Scorpion/GunMount/GunRotor`. Each moving part has a joined mesh with material
  surfaces beneath its named transform. Modules may be removed independently.
- Local tail rest positions: TailBase (0,.22,.68), TailUpper (0,.76,.27),
  TailFore (0,.75,-.67), TailExtension (0,-.22,-1.16), HammerHead (0,0,0).
  The four local-X hinge angles are fraction times (-.90,-.15,.50,.55).
  TailExtension adds .22 metres along (0,-.1863337,-.9824865), using
  `smoothstep(.15,.85,fraction)`. The shared `ScorpionGeometry` drives both
  authoritative queries and this presentation curve.
- Hammer center at rest is (0,1.25,-1.12), size (.62,.76,.50). Its silhouette is
  one octagonal forging with an integrated impact face, skewed crown, recessed
  fasteners, separate wrist and telescoping ram. The front has a .28-wide yellow
  hazard inset with broad physical 45-degree stripes.
- Preserve GunMount's imported -0.035 rad local-X rest pitch. It is authored
  around the muzzle (.66,.27,-1.72); exact mount translation is in the manifest.
  GunRotor spins around its own local Z. The six hollow barrels have .0192 bore
  radius and .48 bore depth, with three scalloped supports containing real holes.
  The receiver includes the side feeder, trunnion, motor, rail and optic.
- Upper/lower leg parts start at a joint origin and extend along local +Y by
  .45 and .73 respectively. The upper coxa is compact and waisted; the lower
  shin has broad sculpted armor and a real open clevis exposing the ankle link.
  Joint cylinders rotate around local X, tangent to the radial stance.
- Source hip positions are (+/-.46,-.13,+/-.68) and (+/-.79,-.13,0); neutral foot
  positions are (+/-.90,-.95,+/-1.10) and (+/-1.40,-.95,0). Feet point radially out.
  Their origin is floor contact and ankle height is .18. Blender's showcase
  uses the same two-link solution and dimensions as the Scorpion runtime.
- Fully assembled detail is 179,366 triangles: 95,726 body/tail/gun, plus six
  copies of 4,484 upper, 6,548 lower and 2,908 foot. Geometry is joined per moving
  part; Godot's generated LODs remain enabled. This count records full source
  detail, not a rendered performance certification.

## Material portability

Shared 1024px map sets cover orange paint, dark chassis metal, parkerized receiver,
nitrided barrels, forged hammer and its hazard marking. Maps supply base color,
packed roughness/metallic (G roughness, B metallic) and tangent normal. Other
fittings use standard Principled PBR. Edge radii use their own surface material;
there is no automatic silver outline on every seam. Selective wear and broken
paint chips are deterministic, while the hammer uses irregular alloy variation.

Artist base colors are encoded sRGB; roughness/metallic and normals are Non-Color.
The generator writes the PNG and reloads it as a file texture so Blender and
Godot sample the same bytes. A verified orange sample is RGB (222,103,15), not
the red-shifted intermediate produced during development. Preserve the checked-in
texture `.import` settings, including mipmap generation and high-quality VRAM
compression. GLBs reference these shared PNGs rather than embedding duplicate
sets in every limb. Keep all referenced maps with the GLBs.

## Validation

Blender rebuilt all parts and rendered beauty/front/left/top views. The main
generator validates external image references and writes exact pivots, extension
data, triangle counts and collider rings to `scorpion_manifest.json`. Native
Godot geometry/pose/combat and garage checks are maintained by the integration
work; source-art renders alone do not establish those gameplay outcomes.
