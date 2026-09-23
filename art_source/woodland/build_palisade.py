"""Woodland palisade modules: wall bays and posts, built for the 16 m wall.

Run: blender --background --python art_source/woodland/build_palisade.py

Outputs battlebots/assets/models/woodland/palisade_<piece>.gltf (+ .bin):
bay_braced, bay_bannered (7.12 m wide bays), post, corner_post.
Frame (Godot, after glTF conversion): x along the wall, y up from the ground,
+z toward the arena; the inner collision plane is z = 0 and nothing crosses
it. Dimensions mirror woodland_visuals.gd (DECK 14.6 m, BUMPER 3.15 m).

Every timber is a bevelled box whose UVs run in metres along the grain (U)
and across it (V), offset per piece, so the scanned wood maps with correct
grain and no two boards match. Planks are warped slightly, have broken or
angled tops and gaps. Straps are forged bands with domed bolt heads. Ambient
occlusion is baked into vertex colour. Material slots: timber, plank, iron.
"""
import bpy, bmesh, math, random, pathlib
from mathutils import Vector, Matrix

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "battlebots/assets/models/woodland"
OUT.mkdir(parents=True, exist_ok=True)
DECK, BUMPER, BAY = 14.6, 3.15, 7.12

prefs = bpy.context.preferences.addons["cycles"].preferences
for device_type in ("OPTIX", "CUDA"):
	try:
		prefs.compute_device_type = device_type
		prefs.get_devices()
		if any(d.type == device_type for d in prefs.devices):
			for d in prefs.devices:
				d.use = d.type == device_type
			break
	except TypeError:
		continue

def G(x, y, z):
	"""Godot (x right, y up, z toward arena) to Blender (x, -z, y)."""
	return Vector((x, -z, y))

def reset():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete()
	for block in (bpy.data.meshes, bpy.data.materials):
		for item in list(block):
			block.remove(item)
	MATS.clear()

MATS = {}
def mat(name):
	if name not in MATS:
		m = bpy.data.materials.new(name)
		m.diffuse_color = {"timber": (0.35, 0.25, 0.16, 1), "plank": (0.45, 0.35, 0.25, 1), "iron": (0.12, 0.12, 0.12, 1)}.get(name, (0.5, 0.5, 0.5, 1))
		MATS[name] = m
	return MATS[name]

rng = random.Random(1234)

def timber(center, size, material, bevel=0.03, rot=(0, 0, 0), warp=0.0, top_cut=0.0, seed=None):
	"""Bevelled box in Godot coordinates. size: (along x, y, z). The longest
	axis is the grain; UVs are metres along/across it, offset per piece."""
	r = random.Random(seed if seed is not None else rng.random())
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
	# Angled or broken top on vertical boards (Godot y = local y).
	if top_cut:
		for v in bm.verts:
			if v.co.y > 0:
				v.co.y -= top_cut * (0.5 + v.co.x / size[0])
	bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=2, profile=0.6, affect="EDGES")
	# Slight bow along the grain.
	axis = max(range(3), key=lambda i: size[i])
	if warp:
		for v in bm.verts:
			t = v.co[axis] / size[axis]
			bend = warp * (1.0 - 4.0 * t * t)
			v.co[(axis + 2) % 3] += bend
	uv = bm.loops.layers.uv.new("UVMap")
	u_off, v_off = r.uniform(0, 20), r.uniform(0, 20)
	for f in bm.faces:
		n = f.normal
		dom = max(range(3), key=lambda i: abs(n[i]))
		across = [i for i in range(3) if i != axis and i != dom]
		across = across[0] if across else (axis + 1) % 3
		for loop in f.loops:
			p = loop.vert.co
			if dom == axis:  # End grain: show rings across both axes.
				others = [i for i in range(3) if i != axis]
				loop[uv].uv = (p[others[0]] + u_off, p[others[1]] + v_off)
			else:
				loop[uv].uv = (p[axis] + u_off, p[across] + v_off)
	mesh = bpy.data.meshes.new("t")
	bm.to_mesh(mesh)
	bm.free()
	o = bpy.data.objects.new("t", mesh)
	bpy.context.collection.objects.link(o)
	o.data.materials.append(mat(material))
	# Godot to Blender basis: rotate so local y (up) is Blender z.
	o.matrix_world = Matrix.Translation(G(*center)) @ Matrix.Rotation(math.pi / 2, 4, "X") @ \
		(Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X") @ Matrix.Rotation(rot[2], 4, "Z"))
	return o

def bolt(at, radius=0.06, normal=(0, 0, 1)):
	"""Domed forged bolt head with a square washer, facing normal (Godot)."""
	n = G(*normal).normalized()
	bpy.ops.mesh.primitive_cube_add(size=1)
	w = bpy.context.object
	w.scale = (radius * 2.4, radius * 2.4, radius * 0.5)
	bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=5, radius=radius)
	h = bpy.context.object
	h.scale = (1, 1, 0.55)
	for o, off in ((w, radius * 0.25), (h, radius * 0.5)):
		o.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
		o.location = G(*at) + n * off
		o.data.materials.append(mat("iron"))
	return [w, h]

def strap(x, y0, y1, z, width=0.32):
	"""Forged vertical strap with slightly irregular edges and bolt heads."""
	o = timber((x, (y0 + y1) / 2, z), (width, y1 - y0, 0.05), "iron", bevel=0.012, seed=int(x * 100))
	parts = [o]
	for y in [y0 + 0.35 + i * (y1 - y0 - 0.7) / 2 for i in range(3)]:
		parts += bolt((x, y, z + 0.03), 0.07)
	return parts

def export(name, prefix="palisade_"):
	bpy.ops.object.select_all(action="SELECT")
	bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	bpy.ops.object.join()
	joined = bpy.context.object
	joined.name = name
	bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
	joined.data.color_attributes.new("ao", "FLOAT_COLOR", "POINT")
	joined.data.color_attributes.active_color = joined.data.color_attributes["ao"]
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.samples = 96
	scene.render.bake.target = "VERTEX_COLORS"
	scene.world = scene.world or bpy.data.worlds.new("w")
	# Contact occlusion only: a short AO distance keeps open faces bright.
	if scene.world is None:
		scene.world = bpy.data.worlds.new("w")
	scene.world.light_settings.distance = 0.35
	bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, -0.02))
	ground = bpy.context.object
	bpy.ops.object.select_all(action="DESELECT")
	joined.select_set(True)
	bpy.context.view_layer.objects.active = joined
	try:
		bpy.ops.object.bake(type="AO")
	except RuntimeError:
		scene.cycles.device = "CPU"
		bpy.ops.object.bake(type="AO")
	bpy.data.objects.remove(ground)
	bpy.ops.export_scene.gltf(filepath=str(OUT / (prefix + name + ".gltf")), export_format="GLTF_SEPARATE",
		use_selection=True, export_materials="EXPORT", export_image_format="NONE", export_apply=True,
		export_vertex_color="ACTIVE")
	print("EXPORT", prefix + name, "tris", sum(len(p.vertices) - 2 for p in joined.data.polygons))

def bay(bannered):
	reset()
	global rng
	rng = random.Random(77 if bannered else 55)
	a, b = -BAY / 2, BAY / 2
	# Impact zone: three hewn beams, slightly uneven, bolted through straps.
	for row in range(3):
		y = 0.525 + row * 1.05
		timber((rng.uniform(-0.03, 0.03), y, -0.42 - rng.uniform(0, 0.03)), (BAY + 0.1, 1.0, 0.78), "timber",
			bevel=0.06, rot=(0, 0, rng.uniform(-0.004, 0.004)), warp=0.02)
	for dx in (-BAY * 0.32, 0.0, BAY * 0.32):
		strap(dx, 0.02, BUMPER - 0.05, -0.02)
	timber((0, BUMPER + 0.07, -0.8), (BAY + 0.1, 0.14, 1.58), "timber", bevel=0.03)
	# Dark backing so plank gaps read as shadow.
	timber((0, (BUMPER + DECK) / 2, -1.64), (BAY + 0.6, DECK - BUMPER, 0.08), "timber", bevel=0.01)
	# Vertical planks: gaps, warp, uneven and broken tops.
	count = int(BAY / 0.56)
	pitch = BAY / count
	for n in range(count):
		x = a + (n + 0.5) * pitch
		top = DECK - 0.3 + rng.uniform(-0.3, 0.12)
		cut = rng.choice([0.0, 0.0, 0.12, -0.12, 0.25])
		timber((x, (BUMPER + top) / 2, -1.45 + rng.uniform(-0.03, 0.03)), (pitch - 0.05, top - BUMPER, 0.14), "plank",
			bevel=0.018, rot=(0, 0, rng.uniform(-0.006, 0.006)), warp=rng.uniform(-0.02, 0.02), top_cut=cut)
	# Girts and diagonal braces.
	for y in (8.0, 13.4):
		timber((0, y, -1.1), (BAY + 0.04, 0.54, 0.44), "timber", bevel=0.04, warp=0.03)
		for n in range(count):
			if n % 2 == 0:
				bolt((a + (n + 0.5) * pitch, y, -0.86), 0.05)
	if not bannered:
		low, high = BUMPER + 0.4, 7.6
		length = math.hypot(BAY - 0.8, high - low)
		angle = math.atan2(high - low, BAY - 0.8)
		timber((0, (low + high) / 2, -1.02), (length, 0.44, 0.28), "timber", bevel=0.035, rot=(0, 0, angle))
		timber((0, (low + high) / 2, -1.06), (length, 0.44, 0.28), "timber", bevel=0.035, rot=(0, 0, -angle))
		bolt((0, (low + high) / 2, -0.86), 0.09)
	export("bay_bannered" if bannered else "bay_braced")

def post():
	reset()
	global rng
	rng = random.Random(9)
	h = DECK + 1.8
	timber((0, h / 2, -0.58), (1.15, h, 1.15), "timber", bevel=0.08, warp=0.02)
	for y in (BUMPER + 0.1, 8.0, 13.4):
		timber((0, y, -0.58), (1.25, 0.26, 1.25), "iron", bevel=0.02)
		for dx in (-0.32, 0.32):
			bolt((dx, y, 0.05), 0.075)
	# Pyramid cap.
	bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.95, depth=0.8, location=G(0, h + 0.4, -0.58))
	cap = bpy.context.object
	cap.rotation_euler = (0, 0, math.pi / 4)
	cap.data.materials.append(mat("iron"))
	export("post")

def corner_post():
	reset()
	global rng
	rng = random.Random(11)
	h = DECK + 3.0
	bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.92, depth=h + 1.0, location=G(0, h / 2 - 0.5, -0.95))
	log = bpy.context.object
	log.data.materials.append(mat("timber"))
	for y in (2.0, 8.0, 13.4, DECK + 2.2):
		bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.97, depth=0.26, location=G(0, y, -0.95))
		bpy.context.object.data.materials.append(mat("iron"))
	export("corner_post")

if __name__ == "__main__":
	bay(False)
	bay(True)
	post()
	corner_post()
	print("PALISADE DONE")
