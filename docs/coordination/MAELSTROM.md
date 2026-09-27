# Frozen Maelstrom — #102

New selectable Practice / Practice Duel / private LAN arena, built on the
Woodland template (deterministic GDScript ground and mirrored obstacle list,
Blender-built models with material slots, a dedicated visuals script).

A whirlpool frozen mid-spin in a frozen sea, where two fleets fought and died.
The playable ice is a ring about Woodland's area (~49,000 m²) tilting down
toward the eye (steepest on the flanks, gentler along the team lanes), with broad
frozen swells, two spiral pressure ridges and slab ramps. The rim stands 0.5 m
over the thin ice of the frozen sea: leaving the ring or falling into the eye
eliminates the bot. Seracs, icicle clusters, barrels and crates break when shot
or rammed. The frozen crew sit in final-moment poses (huddled, slumped,
curled, praying, leaning). Everything beyond the ring is shaded darker. Obstacles: fractured basalt
crags, seracs, and wrecks of the Ember Crown (oxblood, tarnished brass, black
sunburst) and the Jade Covenant (dark verdigris, pewter, bone trident): a
rising bow, a listing stern castle, a deck-ramp platform, a capsized keel
ribcage and standing masts, with frozen crew, torn sails and banners.

Art direction after user review: gothic, mean, realistic dark fantasy (user
reference: hazy blue glacier gorge). Overcast moonlight, heavy freezing fog and
ground mist, desaturated grade; the only warmth is guttering lantern embers.
Earlier passes (saturated aurora, glossy black ice, glowing cracks, gem-like
crystals) were rejected as cartoony.

## Validation (DeskFraph, RTX 4080, 2026-09-27)

- `tests/presentation/maelstrom_arena_test.gd`: area, eye size vs Atlas MX,
  point symmetry, mirrored fleets, hull presence, slopes below 20° on the ice
  (outside ramp slabs), clear and level starts / duel places / pickups /
  cooling points, open edges, headless stripping, capture views.
- `tests/simulation/maelstrom_fall_test.gd`: pads hold a parked bot, lip does not
  slide, eye / sea / driving off the rim eliminate, round reset and Practice
  respawn restore, Woodland keeps its reset rule.
- `tests/network/maelstrom_session_test.gd`: ENet, arena rules 3 rejected, all
  peers build ice and open edges, starts across the eye, eye elimination
  replicated with its reason.
- Heavy spawn, arena spawns, Practice Duel, pickups, selection, menu flow,
  Woodland/Sunreach arena and bridges, baseline, rules smoke.
- Stress (earlier art pass): 12 armed bots 1920x1080 / 20 s, frame median
  14.2 ms, GPU 3.4 ms, physics 3.6 ms. Load: ~0.5 s height grid (server too),
  ~0.3 s art.

Open: the look is under user review. No snow/ice photoscans exist in the repo;
the ice and snow are procedural shaders (CC0 scans would need a download).