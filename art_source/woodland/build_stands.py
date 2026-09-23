"""Woodland stadium structures: grandstand faces, floodlight tower, scoreboard
frame and spectator figures.

Run: blender --background --python art_source/woodland/build_stands.py

Shares the palisade helpers (build_palisade.py): Godot-frame coordinates,
bevelled timbers with metre grain UVs, forged bolts, contact AO baked to vertex
colour. Outputs battlebots/assets/models/woodland/stadium_<piece>.gltf.

Frames (Godot):
- stands_canopy / stands_open: one octagon face. x along the wall, +z toward
  the arena, z = 0 is the palisade's inner plane, y = 0 ground. Includes the
  walkway on the wall top, 12 raked terraces with treads, risers and benches,
  trestle supports to the ground, back wall and (canopy) canvas roofs.
- tower: base centre at the origin, lamp head facing +z.
- scoreboard: centred on the board plane; the screen opening (46 x 24 m,
  centre y 41) is left open for the game's animated screen.
- fan_seated / fan_standing: ~1.75 m person facing +z. Material slots skin,
  shirt, trousers, hair let the game colour every instance differently.
Material slots: timber, plank, iron, canvas, lamp, skin, shirt, trousers, hair.
"""
import bpy, bmesh, math, random, sys, pathlib
from mathutils import Vector, Matrix

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import build_palisade as P

DECK = P.DECK
TIERS = 12
FRONT = -5.5
TREAD = 0.92
TAN = 0.41421356

def beam(a, b, w, d, material, bevel=0.03, up=(0, 1, 0)):
	"""Timber from Godot point a to b, cross-section w (horizontal) x d."""
	a, b = Vector(a), Vector(b)
	length = (b - a).length
	o = P.timber((0, 0, 0), (length, d, w), material, bevel=bevel)
	direction = P.G(*(b - a)).normalized()
	upv = P.G(*up).normalized()
	x = direction
	z = x.cross(upv).normalized() if abs(x.dot(upv)) < 0.99 else x.cross(Vector((1, 0, 0))).normalized()
	y = z.cross(x)
	rot = Matrix((x, y, z)).transposed().to_4x4()
	o.matrix_world = Matrix.Translation(P.G(*((a + b) / 2))) @ rot
	return o

def cloth(corners, sag, material, res=10):
	"""Four Godot corners (a b c d, in order), sagging toward the middle."""
	c = [Vector(p) for p in corners]
	bm = bmesh.new()
	grid = []
	for j in range(res + 1):
		row = []
		for i in range(res + 1):
			u, v = i / res, j / res
			p = c[0].lerp(c[1], u).lerp(c[3].lerp(c[2], u), v)
			p.y -= sag * math.sin(math.pi * u) * math.sin(math.pi * v)
			row.append(bm.verts.new(P.G(*p)))
		grid.append(row)
	uv = bm.loops.layers.uv.new("UVMap")
	for j in range(res):
		for i in range(res):
			f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
			for loop, (du, dv) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
				loop[uv].uv = ((i + du) / res * 6.0, (j + dv) / res * 12.0)
	mesh = bpy.data.meshes.new("cloth")
	bm.to_mesh(mesh)
	bm.free()
	o = bpy.data.objects.new("cloth", mesh)
	bpy.context.collection.objects.link(o)
	o.data.materials.append(P.mat(material))
	mod = o.modifiers.new("thick", "SOLIDIFY")
	mod.thickness = 0.03
	return o

def cyl(center, radius, depth, material, axis="Y", verts=16):
	bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=P.G(*center))
	o = bpy.context.object
	if axis == "Y":
		pass
	elif axis == "Z":
		o.rotation_euler = (math.pi / 2, 0, 0)
	elif axis == "X":
		o.rotation_euler = (0, math.pi / 2, 0)
	o.data.materials.append(P.mat(material))
	return o

def half_width(z):
	return (120.0 - z) * TAN - 4.5

def stands(canopy):
	P.reset()
	P.rng = random.Random(3 if canopy else 4)
	face = 120.0 * TAN
	# Walkway on the wall top: deck boards, joists and a railing.
	P.timber((0, DECK - 0.1, -2.8), (face * 2.0, 0.2, 5.4), "plank", bevel=0.02)
	P.timber((0, DECK - 0.5, -0.3), (face * 2.0, 0.9, 0.5), "timber", bevel=0.04)
	for n in range(int(face * 2.0 / 2.0)):
		x = -face + 1.0 + n * 2.0
		P.timber((x, DECK + 0.55, -0.45), (0.12, 1.1, 0.12), "timber", bevel=0.015)
	P.timber((0, DECK + 1.08, -0.45), (face * 2.0, 0.1, 0.18), "timber", bevel=0.02)
	P.timber((0, DECK + 0.6, -0.45), (face * 2.0, 0.08, 0.07), "timber", bevel=0.01)
	back = FRONT - TREAD * TIERS - 0.2
	for k in range(TIERS):
		z0 = FRONT - TREAD * k
		z1 = z0 - TREAD
		top = DECK + 0.5 * (k + 1)
		hw = half_width((z0 + z1) / 2)
		# Riser, three tread boards and a bench on short legs.
		P.timber((0, top - 0.25, z0 - 0.03), (hw * 2.0, 0.5, 0.06), "plank", bevel=0.01)
		for b in range(3):
			P.timber((P.rng.uniform(-0.05, 0.05), top - 0.03, z0 - 0.16 - b * 0.28), (hw * 2.0, 0.06, 0.26), "plank", bevel=0.012)
		P.timber((0, top + 0.44, z1 + 0.3), (hw * 2.0 - 0.6, 0.06, 0.36), "plank", bevel=0.015)
		leg = 0.0
		while leg < hw * 2.0 - 0.8:
			P.timber((-hw + 0.4 + leg, top + 0.2, z1 + 0.3), (0.08, 0.42, 0.28), "timber", bevel=0.01)
			leg += 2.4
	roof = DECK + 0.5 * TIERS + 3.2
	bw = half_width(back)
	P.timber((0, (DECK + roof + 1.5) / 2, back), (bw * 2.0, roof + 1.5 - DECK, 0.12), "plank", bevel=0.01)
	# Trestle bents every 6 m: posts to the ground, raker, cross bracing.
	x = -bw + 1.0
	while x < bw - 0.5:
		reach = half_width(FRONT)
		if abs(x) < reach:
			beam((x, DECK, FRONT), (x, roof - 1.0, back), 0.28, 0.42, "timber")
			for z in (FRONT, (FRONT + back) / 2, back):
				top = DECK + (FRONT - z) / (FRONT - back) * (roof - 1.0 - DECK) if z != FRONT else DECK
				P.timber((x, top / 2 - 0.3, z), (0.45, top + 0.6, 0.45), "timber", bevel=0.04, warp=0.02)
			beam((x, 1.0, FRONT), (x, DECK - 0.5, back), 0.18, 0.26, "timber")
			beam((x, 1.0, back), (x, DECK - 0.5, FRONT), 0.18, 0.26, "timber")
			for y in (5.0, 10.0):
				P.timber((x, y, (FRONT + back) / 2), (0.2, 0.3, FRONT - back + 0.6), "timber", bevel=0.02)
				P.bolt((x + 0.1, y, FRONT + 0.2), 0.06, normal=(1, 0, 0))
		x += 6.0
	# Longitudinal ties and girts under the terraces.
	for z in (FRONT, back):
		for y in (5.0, 10.0):
			P.timber((0, y, z + 0.25), (half_width(z) * 2.0, 0.28, 0.2), "timber", bevel=0.02)
	if canopy:
		eave = roof - 1.0
		for bay in range(-4, 5):
			x0 = bay * 6.0
			for xp in (x0 - 3.0, x0 + 3.0):
				P.timber((xp, (DECK + eave) / 2, FRONT + 0.2), (0.24, eave - DECK, 0.24), "timber", bevel=0.02)
			P.timber((x0, eave, FRONT + 0.2), (6.2, 0.24, 0.22), "timber", bevel=0.02)
			ridge = (eave + roof) / 2 + 1.4
			beam((x0, ridge, FRONT + 0.6), (x0, ridge, back), 0.16, 0.16, "timber")
			for s in (-1.0, 1.0):
				cloth([(x0, ridge, FRONT + 0.6), (x0 + s * 3.0, eave, FRONT + 0.6), (x0 + s * 3.0, roof, back), (x0, ridge, back)],
					0.25, "canvas")
			cloth([(x0 - 3.0, eave, FRONT + 0.34), (x0 + 3.0, eave, FRONT + 0.34), (x0 + 3.0, eave - 0.7, FRONT + 0.36), (x0 - 3.0, eave - 0.7, FRONT + 0.36)], 0.05, "shirt", 4)
	P.export("stands_canopy" if canopy else "stands_open", "stadium_")

def tower():
	P.reset()
	P.rng = random.Random(8)
	h = 44.0
	s = 2.6
	legs = [(-s, -s), (s, -s), (-s, s), (s, s)]
	for lx, lz in legs:
		P.timber((lx, h / 2 - 1.0, lz), (0.9, h + 2.0, 0.9), "timber", bevel=0.06, warp=0.03)
		P.timber((lx, 0.4, lz), (1.4, 1.3, 1.4), "iron", bevel=0.03)
	levels = 8
	for level in range(levels):
		y0 = 1.5 + level * (h - 1.5) / levels
		y1 = y0 + (h - 1.5) / levels
		for (ax, az), (bx, bz) in (((-s, -s), (s, -s)), ((-s, s), (s, s)), ((-s, -s), (-s, s)), ((s, -s), (s, s))):
			nx = 0.5 * (1 if ax == bx and ax > 0 else -1 if ax == bx else 0)
			nz = 0.5 * (1 if az == bz and az > 0 else -1 if az == bz else 0)
			beam((ax + nx, y0, az + nz), (bx + nx, y1, bz + nz), 0.2, 0.32, "timber")
			beam((bx + nx * 1.4, y0, bz + nz * 1.4), (ax + nx * 1.4, y1, az + nz * 1.4), 0.2, 0.32, "timber")
			beam((ax + nx, y1, az + nz), (bx + nx, y1, bz + nz), 0.36, 0.4, "timber")
			P.bolt(((ax + bx) / 2 + nx * 1.6, (y0 + y1) / 2, (az + bz) / 2 + nz * 1.6), 0.09,
				normal=(1 if nx > 0 else -1 if nx < 0 else 0, 0, 1 if nz > 0 else -1 if nz < 0 else 0))
	# Ladder up the back face.
	for side in (-0.4, 0.4):
		P.timber((side, h / 2, -s - 0.8), (0.1, h, 0.1), "iron", bevel=0.01)
	for n in range(int(h / 0.4)):
		P.timber((0, 0.4 + n * 0.4, -s - 0.8), (0.8, 0.04, 0.04), "iron", bevel=0.005)
	# Platform, rail and roof.
	P.timber((0, h, 0), (7.0, 0.3, 7.0), "plank", bevel=0.03)
	for n in range(12):
		P.timber((-3.3 + n * 0.6, h - 0.3, 0), (0.18, 0.3, 7.0), "timber", bevel=0.02)
	for sx in (-1, 1):
		P.timber((sx * 3.4, h + 1.1, 0), (0.12, 0.12, 6.8), "iron", bevel=0.01)
		P.timber((0, h + 1.1, sx * 3.4), (6.8, 0.12, 0.12), "iron", bevel=0.01)
		for n in range(5):
			P.timber((sx * 3.4, h + 0.55, -3.0 + n * 1.5), (0.1, 1.1, 0.1), "iron", bevel=0.01)
			P.timber((-3.0 + n * 1.5, h + 0.55, sx * 3.4), (0.1, 1.1, 0.1), "iron", bevel=0.01)
	# Lamp head: frame, six housings with hoods, rims and lenses.
	tilt = math.radians(22)
	head = Vector((0, h + 3.2, 2.6))
	def aimed(v):
		# Rotate a head-local offset by the downward tilt about x.
		# Forward (+z) dips toward the arena floor.
		return Vector((v.x, v.y * math.cos(tilt) - v.z * math.sin(tilt), v.y * math.sin(tilt) + v.z * math.cos(tilt)))
	frame = P.timber(tuple(head), (7.4, 4.8, 0.3), "iron", bevel=0.04)
	frame.matrix_world = Matrix.Translation(P.G(*(head + aimed(Vector((0, 0, -0.2)))))) @ Matrix.Rotation(tilt, 4, "X") @ Matrix.Rotation(math.pi / 2, 4, "X")
	for row in range(2):
		for col in range(3):
			c = head + aimed(Vector((-2.3 + col * 2.3, -1.1 + row * 2.2, 0.35)))
			for part, radius, depth, offset, material in (("body", 0.95, 0.9, 0.0, "iron"), ("rim", 1.02, 0.12, 0.45, "iron"), ("lens", 0.85, 0.04, 0.5, "lamp")):
				p = c + aimed(Vector((0, 0, offset)))
				o = cyl(tuple(p), radius, depth, material, "Z", 24)
				o.rotation_euler = (math.pi / 2 + tilt, 0, 0)
			hood = P.timber(tuple(c + aimed(Vector((0, 0.95, 0.4)))), (2.1, 0.06, 0.9), "iron", bevel=0.01)
	bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=6.2, depth=2.8, location=P.G(0, h + 7.0, 0.8))
	roof = bpy.context.object
	roof.rotation_euler = (0, 0, math.pi / 4)
	roof.data.materials.append(P.mat("iron"))
	P.timber((0, h + 5.4, 0.8), (0.4, 2.4, 0.4), "timber", bevel=0.02)
	P.export("tower", "stadium_")

def scoreboard():
	P.reset()
	P.rng = random.Random(12)
	h = 56.0
	for x in (-25.0, 25.0):
		for dz in (-2.0, 2.0):
			P.timber((x, h / 2, dz), (1.2, h, 1.2), "timber", bevel=0.06, warp=0.03)
		for level in range(10):
			y = 1.0 + level * 5.2
			beam((x, y, -2.0), (x, y + 5.2, 2.0), 0.3, 0.4, "timber")
			beam((x, y, 2.0), (x, y + 5.2, -2.0), 0.3, 0.4, "timber")
			P.timber((x, y + 5.2, 0), (0.5, 0.5, 4.6), "timber", bevel=0.03)
			for side in (-1, 1):
				P.bolt((x + side * 0.62, y + 2.6, 0), 0.09, normal=(side, 0, 0))
	# Frame around the screen opening, a riveted backing and a roof.
	for y in (27.2, h - 1.0):
		P.timber((0, y, 0), (52.0, 1.6, 4.6), "timber", bevel=0.05, warp=0.04)
	for x in (-24.0, 24.0):
		P.timber((x, 41.0, -0.4), (1.2, 26.0, 1.2), "iron", bevel=0.03)
	P.timber((0, 41.0, -1.0), (48.0, 26.0, 0.4), "iron", bevel=0.02)
	for n in range(24):
		P.timber((-23.0 + n * 2.0, 41.0, -0.78), (0.14, 25.5, 0.06), "iron", bevel=0.01)
	P.timber((0, h + 1.2, 0), (56.0, 0.4, 8.0), "iron", bevel=0.03)
	for x in (-18.0, -6.0, 6.0, 18.0):
		P.timber((x, h + 0.3, 2.8), (2.4, 1.4, 1.2), "iron", bevel=0.03)
		P.timber((x, h - 0.3, 3.2), (2.0, 0.12, 0.8), "lamp", bevel=0.01)
	P.export("scoreboard", "stadium_")

def fan(seated):
	"""Low-poly spectator, 1.75 m standing, facing +z (Godot)."""
	P.reset()
	parts = []
	def blob(center, size, material, segs=6):
		bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=4, radius=0.5, location=P.G(*center))
		o = bpy.context.object
		o.scale = (size[0], size[2], size[1])
		o.data.materials.append(P.mat(material))
		parts.append(o)
		return o
	def limb(a, b, r, material):
		a, b = Vector(a), Vector(b)
		o = cyl(tuple((a + b) / 2), r, (b - a).length, material, "Y", 5)
		direction = P.G(*(b - a)).normalized()
		o.rotation_mode = "QUATERNION"
		o.rotation_quaternion = direction.to_track_quat("Z", "Y") @ Matrix.Rotation(math.pi / 2, 4, "X").to_quaternion()
		parts.append(o)
	hip = 0.48 if seated else 0.92
	# Legs.
	for sx in (-0.1, 0.1):
		if seated:
			limb((sx, hip, 0.0), (sx, hip, 0.42), 0.075, "trousers")
			limb((sx, hip, 0.42), (sx, 0.05, 0.45), 0.065, "trousers")
			blob((sx, 0.04, 0.52), (0.11, 0.08, 0.26), "hair")
		else:
			limb((sx, hip, 0.0), (sx * 1.1, 0.07, 0.02), 0.075, "trousers")
			blob((sx * 1.1, 0.04, 0.08), (0.11, 0.08, 0.26), "hair")
	blob((0, hip + 0.06, 0), (0.36, 0.2, 0.24), "trousers")
	# Torso, shoulders, arms.
	blob((0, hip + 0.33, 0.0), (0.4, 0.52, 0.24), "shirt", 8)
	for sx in (-1, 1):
		shoulder = Vector((sx * 0.21, hip + 0.52, 0.0))
		elbow = shoulder + Vector((sx * 0.05, -0.27, 0.08))
		hand = elbow + Vector((sx * -0.02, -0.02, 0.26)) if seated else elbow + Vector((0, -0.25, 0.05))
		limb(tuple(shoulder), tuple(elbow), 0.055, "shirt")
		limb(tuple(elbow), tuple(hand), 0.045, "skin")
	# Neck, head, hair.
	limb((0, hip + 0.6, 0), (0, hip + 0.7, 0.01), 0.05, "skin")
	blob((0, hip + 0.8, 0.01), (0.19, 0.24, 0.21), "skin", 7)
	blob((0, hip + 0.86, -0.02), (0.2, 0.18, 0.2), "hair", 7)
	P.export("fan_seated" if seated else "fan_standing", "stadium_")

def fan_low(seated):
	"""Distant-crowd LOD: a few boxes with the same slots and silhouette."""
	P.reset()
	hip = 0.48 if seated else 0.92
	def block(center, size, material):
		P.timber(center, size, material, bevel=0.0)
	if seated:
		block((0, hip, 0.2), (0.34, 0.14, 0.44), "trousers")
		block((0, hip * 0.5, 0.42), (0.3, hip, 0.14), "trousers")
	else:
		block((0, hip * 0.5, 0), (0.32, hip, 0.2), "trousers")
	block((0, hip + 0.3, 0), (0.42, 0.58, 0.24), "shirt")
	block((0, hip + 0.8, 0.01), (0.2, 0.24, 0.21), "skin")
	block((0, hip + 0.93, -0.01), (0.21, 0.07, 0.22), "hair")
	P.export("fan_seated_low" if seated else "fan_standing_low", "stadium_")

stands(True)
stands(False)
tower()
scoreboard()
fan(True)
fan(False)
fan_low(True)
fan_low(False)
print("STADIUM DONE")
