"""Conifer branch-spray atlas from the CC0 fir_sapling_medium scan.

Run: blender --background --python art_source/woodland/build_branch_atlas.py -- <scan_dir>
Writes battlebots/assets/textures/woodland/conifer_branches.png (colour + alpha)
and conifer_branches_nor.png (tangent-space normals, OpenGL): a 2x4 atlas of
1024x512 cells. Each cell is one branch spray seen from above: the scanned
sapling cut to an azimuth wedge and a ~1 m height band, trunk removed, rotated
so the branch grows from the cell's left edge (u = 0, v = 0.5) toward +u.
The game bends these cards into drooping branches around a modelled trunk.
"""
import bpy, bmesh, sys, glob, math, pathlib
import numpy as np
from mathutils import Vector, Matrix

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "battlebots/assets/textures/woodland"
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
scan_dir = pathlib.Path(args[0])
CELL_W, CELL_H, COLS, ROWS = 1024, 512, 2, 4
REACH = 2.3      # Branch length captured (m).
HALF_WIDTH = 0.55  # Half the card's width (m).

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=glob.glob(str(scan_dir / "fir_sapling_medium" / "*.gltf"))[0])
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
source = [o for o in objs if "a_LOD0" in o.name][0]
for o in bpy.context.scene.objects:
	if o is not source:
		bpy.data.objects.remove(o)
source.parent = None
bpy.context.view_layer.objects.active = source
source.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = np.array([v.co[:] for v in source.data.vertices])
trunk = Vector((float(np.median(co[:, 0])), float(np.median(co[:, 1])), 0.0))
z_low, z_high = float(co[:, 2].min()), float(co[:, 2].max())
print("SAPLING", tuple(round(c, 2) for c in trunk), round(z_low, 2), round(z_high, 2))

scene = bpy.context.scene
scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
for device_type in ("OPTIX", "CUDA"):
	try:
		prefs.compute_device_type = device_type
		prefs.get_devices()
		if any(d.type == device_type for d in prefs.devices):
			for d in prefs.devices:
				d.use = d.type == device_type
			scene.cycles.device = "GPU"
			break
	except TypeError:
		continue
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.render.resolution_x, scene.render.resolution_y = CELL_W, CELL_H
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("sky")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
cam_data = bpy.data.cameras.new("card")
cam_data.type = "ORTHO"
cam_data.ortho_scale = REACH
cam = bpy.data.objects.new("card", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

def render(path):
	scene.render.filepath = str(path)
	try:
		bpy.ops.render.render(write_still=True)
	except RuntimeError as error:
		print("GPU render failed, using CPU:", error)
		scene.cycles.device = "CPU"
		bpy.ops.render.render(write_still=True)
	img = bpy.data.images.load(str(path))
	px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL_H, CELL_W, 4)
	bpy.data.images.remove(img)
	path.unlink()
	return px

def wedge(azimuth, z):
	"""Copy of the sapling cut to one branch region, rotated to +x."""
	piece = source.copy()
	piece.data = source.data.copy()
	piece.hide_render = False
	scene.collection.objects.link(piece)
	bm = bmesh.new()
	bm.from_mesh(piece.data)
	bmesh.ops.translate(bm, verts=bm.verts, vec=-trunk)
	bmesh.ops.rotate(bm, verts=bm.verts, cent=Vector(), matrix=Matrix.Rotation(-azimuth, 3, "Z"))
	# Keep 0.12 < x, |y| < HALF_WIDTH, z within the band; bisect and clear.
	for plane_co, plane_no in (((0.12, 0, 0), (-1, 0, 0)), ((0, HALF_WIDTH, 0), (0, 1, 0)), ((0, -HALF_WIDTH, 0), (0, -1, 0)),
			((0, 0, z + 0.55), (0, 0, 1)), ((0, 0, z - 0.45), (0, 0, -1)), ((REACH + 0.1, 0, 0), (1, 0, 0))):
		geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
		bmesh.ops.bisect_plane(bm, geom=geom, plane_co=plane_co, plane_no=plane_no, clear_outer=True)
	bm.to_mesh(piece.data)
	bm.free()
	return piece

atlas = np.zeros((ROWS * CELL_H, COLS * CELL_W, 4), dtype=np.float32)
normals = np.zeros_like(atlas)
source.hide_render = True
# Normal pass material: object-space normal remapped, rendered as emission.
nor_mat = bpy.data.materials.new("normals")
nor_mat.use_nodes = True
nt = nor_mat.node_tree
nt.nodes.clear()
geo = nt.nodes.new("ShaderNodeNewGeometry")
mapping = nt.nodes.new("ShaderNodeVectorMath")
mapping.operation = "MULTIPLY_ADD"
mapping.inputs[1].default_value = (0.5, 0.5, 0.5)
mapping.inputs[2].default_value = (0.5, 0.5, 0.5)
emit = nt.nodes.new("ShaderNodeEmission")
outp = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(geo.outputs["Normal"], mapping.inputs[0])
nt.links.new(mapping.outputs[0], emit.inputs[0])
nt.links.new(emit.outputs[0], outp.inputs[0])
cells = [(0.3, 0.33), (1.4, 0.40), (2.5, 0.47), (3.6, 0.54), (4.7, 0.60), (5.8, 0.33), (0.9, 0.47), (2.0, 0.40)]
for cell, (azimuth, t) in enumerate(cells):
	z = z_low + (z_high - z_low) * t
	# Three neighbouring wedges layered into one dense spray.
	pieces = [wedge(azimuth + k * 2.1, z + k * 0.35) for k in range(3)]
	for k, other in enumerate(pieces[1:], 1):
		other.location.z = -k * 0.35
	piece = pieces[0]
	cam.location = (REACH / 2 + 0.12, 0.0, z + 20.0)
	cam.rotation_euler = (0, 0, 0)
	cam_data.clip_start = 1.0
	cam_data.clip_end = 40.0
	cam_data.ortho_scale = REACH
	colour = render(OUT / "_branch.png")
	saved = [m for m in piece.data.materials]
	for each in pieces:
		for i in range(len(each.data.materials)):
			each.data.materials[i] = nor_mat
	scene.view_settings.view_transform = "Raw" if "Raw" in [v.identifier for v in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Standard"
	nrm = render(OUT / "_branch_nor.png")
	scene.view_settings.view_transform = "Standard"
	for each in pieces:
		bpy.data.objects.remove(each)
	r, c = divmod(cell, COLS)
	y0 = (ROWS - 1 - r) * CELL_H
	atlas[y0:y0 + CELL_H, c * CELL_W:(c + 1) * CELL_W] = colour
	normals[y0:y0 + CELL_H, c * CELL_W:(c + 1) * CELL_W] = nrm
	print("CELL", cell, "coverage", round(float((colour[..., 3] > 0.5).mean()), 3))

opaque = atlas[..., 3] > 0.5
atlas[~opaque, :3] = atlas[opaque, :3].mean(axis=0)
normals[..., 3] = atlas[..., 3]
normals[~opaque, :3] = (0.5, 0.5, 1.0)
for name, data in (("conifer_branches", atlas), ("conifer_branches_nor", normals)):
	img = bpy.data.images.new(name, COLS * CELL_W, ROWS * CELL_H, alpha=True)
	img.pixels.foreach_set(data.ravel())
	if name.endswith("_nor"):
		img.colorspace_settings.name = "Non-Color"
	img.filepath_raw = str(OUT / (name + ".png"))
	img.file_format = "PNG"
	img.save()
print("BRANCH ATLAS DONE")
