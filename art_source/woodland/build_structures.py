"""Woodland obstacle models: steel-and-concrete jump ramps and bunkers.

Run: blender --background --python art_source/woodland/build_structures.py

Geometry matches woodland_ground.gd's collision exactly (ramp wedge, bunker
boxes), so what players see is what they hit. Materials are named slots only
("concrete", "steel", "rust", "slot", "hazard"); the game assigns its scanned
triplanar materials by slot name, so no textures are embedded. Outputs
battlebots/assets/models/woodland/<name>.gltf (+ .bin). Blender is Z-up; glTF
export maps Blender (x, y, z) to Godot (x, z, -y), so the ramp rises toward
Godot -Z and the game rotates it half a turn to match the collision wedge,
which rises toward +Z.
"""
import bpy, bmesh, math, pathlib
from mathutils import Vector, Matrix

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "battlebots/assets/models/woodland"
OUT.mkdir(parents=True, exist_ok=True)
# Mirrors woodland_ground.gd.
RAMP_LENGTH, RAMP_WIDTH, RAMP_HEIGHT = 15.0, 8.0, 3.6
BUNKERS = {"bunker_large": (15.0, 5.2, 8.0), "bunker_medium": (12.0, 4.6, 7.0), "bunker_small": (9.0, 4.0, 6.0)}

def reset():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete()
	for block in (bpy.data.meshes, bpy.data.materials):
		for item in list(block):
			block.remove(item)

def material(name, color):
	m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	m.diffuse_color = (*color, 1.0)
	return m

MATS = {}
def mats():
	MATS.update({"concrete":material("concrete", (0.5, 0.49, 0.46)), "steel":material("steel", (0.32, 0.32, 0.31)),
		"rust":material("rust", (0.35, 0.2, 0.12)), "slot":material("slot", (0.02, 0.02, 0.02)),
		"hazard":material("hazard", (0.85, 0.62, 0.08))})

def finish(obj, mat, bevel=0.0, segments=2):
	obj.data.materials.append(MATS[mat])
	if bevel > 0:
		mod = obj.modifiers.new("edge", "BEVEL")
		mod.width = bevel
		mod.segments = segments
		mod.limit_method = "ANGLE"
	return obj

def box(center, size, mat, bevel=0.03, rotation=(0, 0, 0)):
	bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=rotation)
	o = bpy.context.object
	o.scale = size
	bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	return finish(o, mat, bevel)

def prism(points_2d, x0, x1, mat, bevel=0.04):
	"""Extrude a Y/Z profile (Blender y forward, z up) between x0 and x1."""
	mesh = bpy.data.meshes.new("prism")
	bm = bmesh.new()
	front = [bm.verts.new((x0, y, z)) for y, z in points_2d]
	back = [bm.verts.new((x1, y, z)) for y, z in points_2d]
	bm.faces.new(front[::-1])
	bm.faces.new(back)
	n = len(points_2d)
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new((front[i], front[j], back[j], back[i]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(mesh)
	bm.free()
	o = bpy.data.objects.new("prism", mesh)
	bpy.context.collection.objects.link(o)
	return finish(o, mat, bevel)

def rivet_row(a, b, count, normal, radius=0.045):
	a, b, normal = Vector(a), Vector(b), Vector(normal).normalized()
	objs = []
	for i in range(count):
		p = a.lerp(b, (i + 0.5) / count)
		bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=radius, location=p)
		o = bpy.context.object
		o.scale = (1, 1, 0.55)
		o.rotation_euler = normal.to_track_quat("Z", "Y").to_euler()
		objs.append(finish(o, "steel"))
	return objs

def export(name):
	bpy.ops.object.select_all(action="SELECT")
	for o in bpy.context.selected_objects:
		for mod in o.modifiers:
			bpy.context.view_layer.objects.active = o
			bpy.ops.object.modifier_apply(modifier=mod.name)
	# Bake every object's transform into its vertices before joining, so the
	# single exported mesh sits in the model's own frame with an identity node.
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	bpy.ops.object.join()
	joined = bpy.context.object
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	joined.name = name
	bpy.ops.object.shade_auto_smooth(angle=math.radians(35))
	# Bake ambient occlusion into vertex colours (glTF COLOR_0): contact shadow
	# around rivets, bands, buttresses and the ground line, multiplied in game.
	joined.data.color_attributes.new("ao", "FLOAT_COLOR", "POINT")
	joined.data.color_attributes.active_color = joined.data.color_attributes["ao"]
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.samples = 128
	scene.render.bake.target = "VERTEX_COLORS"
	scene.render.bake.use_selected_to_active = False
	# Contact occlusion only: a short AO distance keeps open faces bright.
	if scene.world is None:
		scene.world = bpy.data.worlds.new("w")
	scene.world.light_settings.distance = 0.35
	bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.02))
	ground = bpy.context.object
	bpy.ops.object.select_all(action="DESELECT")
	joined.select_set(True)
	bpy.context.view_layer.objects.active = joined
	bpy.ops.object.bake(type="AO")
	bpy.data.objects.remove(ground)
	bpy.ops.export_scene.gltf(filepath=str(OUT / (name + ".gltf")), export_format="GLTF_SEPARATE",
		use_selection=True, export_materials="EXPORT", export_image_format="NONE", export_apply=True,
		export_vertex_color="ACTIVE")
	tris = sum(len(p.vertices) - 2 for p in joined.data.polygons)
	print("STRUCTURE", name, "tris", tris)

def build_ramp():
	reset(); mats()
	w, l, h = RAMP_WIDTH / 2, RAMP_LENGTH / 2, RAMP_HEIGHT
	# Concrete body matching the collision wedge (y = rising direction).
	profile = [(-l - 0.6, -0.6), (l, -0.6), (l, h), (l - 1.6, h)]
	prism(profile, -w + 0.35, w - 0.35, "concrete", 0.06)
	# Heavy side cheeks, slightly taller than the deck so the edge reads as a frame.
	for x0, x1 in ((-w, -w + 0.4), (w - 0.4, w)):
		prism([(-l - 0.6, -0.6), (l, -0.6), (l, h + 0.12), (l - 1.6, h + 0.12), (-l - 0.6, -0.48)], x0, x1, "concrete", 0.05)
	# Steel deck plates with gaps, rivets along every seam, anti-slip ribs.
	slope = math.atan2(h + 0.6, (l - 1.6) - (-l - 0.6))
	deck_len = math.hypot(h + 0.6, (l - 1.6) - (-l - 0.6))
	up = Vector((0, -math.sin(slope), math.cos(slope)))
	along = Vector((0, math.cos(slope), math.sin(slope)))
	start = Vector((0, -l - 0.6, -0.6))
	plates = 5
	for i in range(plates):
		mid = start + along * deck_len * (i + 0.5) / plates + up * 0.05
		box(mid, (w * 2 - 0.9, deck_len / plates - 0.06, 0.08), "steel", 0.015, (slope, 0, 0))
		for x in (-w + 0.6, w - 0.6):
			a = start + along * deck_len * i / plates + up * 0.11
			b = start + along * deck_len * (i + 1) / plates + up * 0.11
			rivet_row(a + Vector((x, 0, 0)), b + Vector((x, 0, 0)), 6, up)
		seam = start + along * deck_len * (i + 1) / plates + up * 0.11
		rivet_row(seam + Vector((-w + 0.7, 0, 0)), seam + Vector((w - 0.7, 0, 0)), 12, up)
		for k in range(6):
			rib = start + along * deck_len * (i + (k + 0.5) / 6) / plates + up * 0.1
			box(rib, (w * 2 - 1.4, 0.05, 0.035), "rust", 0.008, (slope, 0, 0))
	# Angle-iron edge rails and corner guards.
	for x in (-w + 0.2, w - 0.2):
		mid = start + along * deck_len * 0.5 + up * 0.18
		box(mid + Vector((x, 0, 0)), (0.3, deck_len, 0.12), "steel", 0.01, (slope, 0, 0))
		box((x, l - 0.8, h + 0.1), (0.46, 1.7, 0.2), "steel", 0.02)
		box((x, l + 0.02, h / 2 - 0.3), (0.5, 0.08, h + 0.6), "steel", 0.01)
		rivet_row((x, l + 0.08, -0.3), (x, l + 0.08, h - 0.1), 8, (0, 1, 0), 0.05)
	# Lip: steel cap and a yellow/black hazard band on the drop face.
	box((0, l - 0.8, h + 0.05), (w * 2 - 0.8, 1.6, 0.1), "steel", 0.01)
	for i in range(10):
		x = -w + 0.6 + i * (w * 2 - 1.2) / 9
		box((x, l + 0.05, h - 0.35), (0.42, 0.04, 0.6), "hazard" if i % 2 == 0 else "slot", 0.0, (0, 0.55, 0))
	export("jump_ramp")

def prism_xz(points_xz, y0, y1, mat, bevel=0.03):
	"""Extrude an X/Z profile between y0 and y1."""
	mesh = bpy.data.meshes.new("prism")
	bm = bmesh.new()
	front = [bm.verts.new((x, y0, z)) for x, z in points_xz]
	back = [bm.verts.new((x, y1, z)) for x, z in points_xz]
	bm.faces.new(front)
	bm.faces.new(back[::-1])
	n = len(points_xz)
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new((front[i], back[i], back[j], front[j]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(mesh)
	bm.free()
	o = bpy.data.objects.new("prism", mesh)
	bpy.context.collection.objects.link(o)
	return finish(o, mat, bevel)

def build_bunker(name, size):
	"""Everything stays inside the collision box (size.x wide, size.z deep)."""
	reset(); mats()
	sx, sy, sz = size[0] / 2, size[2] / 2, size[1]
	inset = 0.12
	# Concrete core just inside the box, buried 0.5 m, with a chamfered roof slab.
	box((0, 0, sz / 2 - 0.25), (size[0] - inset * 2, size[2] - inset * 2, sz + 0.5), "concrete", 0.08)
	box((0, 0, sz + 0.12), (size[0] - 1.2, size[2] - 1.2, 0.3), "concrete", 0.1)
	# Sloped steel-clad corner buttresses, outer faces on the collision box.
	for cx in (-1, 1):
		for cy in (-1, 1):
			outer, inner = cx * sx, cx * (sx - 1.7)
			profile = [(inner, -0.5), (outer, -0.5), (outer, sz * 0.45), (cx * (sx - 1.0), sz + 0.05), (inner, sz + 0.05)]
			if cx < 0:
				profile = profile[::-1]
			y0, y1 = sorted((cy * sy, cy * (sy - 1.6)))
			prism_xz(profile, y0, y1, "steel", 0.03)
			for k in range(4):
				z = 0.25 + k * (sz * 0.45 - 0.3) / 3
				rivet_row((outer + cx * 0.02, y0 + 0.2, z), (outer + cx * 0.02, y1 - 0.2, z), 4, (cx, 0, 0), 0.05)
	# Riveted steel bands, a firing slot and rusted repair plates on the long faces.
	for face in (-1, 1):
		y = face * (sy - inset + 0.03)
		for z in (0.55, sz - 0.45):
			box((0, y, z), (size[0] - 3.8, 0.06, 0.38), "steel", 0.01)
			rivet_row((-sx + 2.0, y + face * 0.04, z), (sx - 2.0, y + face * 0.04, z), int(size[0] / 0.7), (0, face, 0), 0.05)
		box((0, y - face * 0.05, sz * 0.66), (size[0] * 0.5, 0.2, 0.5), "slot", 0.0)
		box((0, y, sz * 0.66 + 0.33), (size[0] * 0.54, 0.1, 0.12), "steel", 0.01)
		for i in (-1, 0, 1):
			box((i * size[0] * 0.28, y + face * 0.01, sz * 0.36), (1.3, 0.04, 1.1), "rust", 0.01)
	# Roof hatch and lifting eyes.
	box((sx * 0.4, 0, sz + 0.33), (1.5, 1.5, 0.12), "steel", 0.02)
	for x in (-sx * 0.6, sx * 0.6):
		bpy.ops.mesh.primitive_torus_add(major_radius=0.22, minor_radius=0.05, location=(x, 0, sz + 0.45), rotation=(math.pi / 2, 0, 0))
		finish(bpy.context.object, "steel")
	export(name)

build_ramp()
for name, size in BUNKERS.items():
	build_bunker(name, size)
print("STRUCTURES DONE")
