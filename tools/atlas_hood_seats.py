"""Audit/recess Atlas hood backing caps without rebaking the approved UVs/maps.

python tools/atlas_hood_seats.py [--write]
blender --background art_source/atlas_mx/atlas_mx.blend --python tools/atlas_hood_seats.py -- --source --write
The source generator independently authors the same recessed end planes.
"""
import json
import math
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from atlas_front_shell import TERMINAL_SEAT_END_INSET

INNER, OUTER, DROP = .891, 1.002, .065
FACTOR = (OUTER - INNER - 2 * TERMINAL_SEAT_END_INSET) / (OUTER - INNER)
NAMES = {'DriveLeftSurface', 'DriveRightSurface', 'SponsonLeft', 'SponsonRight'}


def components(points, faces):
    parents = list(range(len(points)))
    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i
    seen = {}
    for i, point in enumerate(points):
        key = tuple(round(x, 6) for x in point)
        if key in seen:
            parents[find(i)] = find(seen[key])
        else:
            seen[key] = i
    for face in faces:
        for i in face[1:]:
            parents[find(i)] = find(face[0])
    groups = {}
    for i in range(len(points)):
        groups.setdefault(find(i), []).append(i)
    return list(groups.values())


def seat_groups(points, faces):
    result = []
    for ids in components(points, faces):
        low = [min(points[i][axis] for i in ids) for axis in range(3)]
        high = [max(points[i][axis] for i in ids) for axis in range(3)]
        # Backing is 6 mm below and 2 mm inboard of the enamel hood. It is a
        # separate connected solid, even when a glTF material splits its UVs.
        if low[1] > .32 and high[1] < .495 and (low[2] > .89 or high[2] < -.89):
            result.append(ids)
    assert len(result) == 2, f'Expected front/rear seats, found {len(result)}'
    return result


def recess(point):
    x, y, z = point
    new_z = math.copysign(INNER + TERMINAL_SEAT_END_INSET + (abs(z) - INNER) * FACTOR, z)
    return x, y - (abs(new_z) - abs(z)) * DROP / (OUTER - INNER), new_z


def normal_after(normal, z):
    # Inverse transpose of the Y/Z shear and Z compression; keep bevel normals.
    x, y, n_z = normal
    shear = math.copysign((1 - FACTOR) * DROP / (OUTER - INNER), z)
    n_z = (n_z - shear * y) / FACTOR
    length = math.sqrt(x*x + y*y + n_z*n_z)
    return x/length, y/length, n_z/length


def clearances(points, groups):
    return [min(min(abs(points[i][2]) for i in ids) - INNER,
                OUTER - max(abs(points[i][2]) for i in ids)) for ids in groups]


def glb(path, write=False):
    raw = bytearray(path.read_bytes())
    json_size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+json_size])
    binary = 28 + json_size
    def layout(index):
        a = doc['accessors'][index]
        b = doc['bufferViews'][a['bufferView']]
        width = {'SCALAR':1, 'VEC2':2, 'VEC3':3, 'VEC4':4}[a['type']]
        fmt = '<' + {5126:'f', 5125:'I', 5123:'H', 5121:'B'}[a['componentType']] * width
        return a, fmt, binary+b.get('byteOffset',0)+a.get('byteOffset',0), b.get('byteStride',struct.calcsize(fmt))
    def read(index):
        a, fmt, offset, stride = layout(index)
        return [struct.unpack_from(fmt, raw, offset+i*stride) for i in range(a['count'])]
    def put(index, item, values):
        _, fmt, offset, stride = layout(index)
        struct.pack_into(fmt, raw, offset+item*stride, *values)
    report = {}
    changed_accessors = set()
    for node in doc['nodes']:
        if node.get('name') not in NAMES: continue
        prims = doc['meshes'][node['mesh']]['primitives']
        points, faces, refs = [], [], []
        for pi, p in enumerate(prims):
            offset = len(points)
            vertices = read(p['attributes']['POSITION'])
            points.extend(vertices)
            refs.extend((pi, i) for i in range(len(vertices)))
            indices = [v[0]+offset for v in read(p['indices'])]
            faces.extend(indices[i:i+3] for i in range(0,len(indices),3))
        groups = seat_groups(points, faces)
        gaps = clearances(points, groups)
        if write:
            assert all(abs(gap) < 1e-6 for gap in gaps), 'Already recessed or unexpected source'
            for ids in groups:
                normals = {pi:read(p['attributes']['NORMAL']) for pi,p in enumerate(prims)}
                for i in ids:
                    pi, vi = refs[i]
                    attributes = prims[pi]['attributes']
                    changed_accessors.update((attributes['POSITION'], attributes['NORMAL']))
                    put(attributes['POSITION'], vi, recess(points[i]))
                    put(attributes['NORMAL'], vi, normal_after(normals[pi][vi], points[i][2]))
            # Indices, UVs, materials and unrelated vertex buffers stay exact.
        report[node['name']] = {'seat_vertices':sum(map(len,groups)), 'minimum_cap_gap_m':min(gaps)}
    assert len(report) == 2
    if write:
        for index in changed_accessors:
            a = doc['accessors'][index]
            values = read(index)
            for key, operation in [('min', min), ('max', max)]:
                if key in a:
                    a[key] = [operation(v[axis] for v in values) for axis in range(3)]
        encoded = json.dumps(doc,separators=(',',':')).encode()
        encoded += b' ' * (-len(encoded)%4)
        payload = raw[binary:]
        path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(payload)) +
                         struct.pack('<I4s',len(encoded),b'JSON') + encoded +
                         struct.pack('<I4s',len(payload),b'BIN\0') + payload)
    return report


def source(write=False):
    import bpy
    obj_report = {}
    for name in ['DriveLeftSurface','DriveRightSurface']:
        mesh = bpy.data.objects[name].data
        points = [(v.co.x,v.co.z,-v.co.y) for v in mesh.vertices]
        groups = seat_groups(points, [list(p.vertices) for p in mesh.polygons])
        gaps = clearances(points, groups)
        if write:
            assert all(abs(gap)<1e-6 for gap in gaps), 'Source is already recessed'
            ids = {i for group in groups for i in group}
            normals = [(n.vector.x,n.vector.z,-n.vector.y) for n in mesh.corner_normals]
            for loop in mesh.loops:
                if loop.vertex_index in ids:
                    normals[loop.index] = normal_after(normals[loop.index], points[loop.vertex_index][2])
            for i in ids:
                x,y,z = recess(points[i]); mesh.vertices[i].co = (x,-z,y)
            mesh.update()
            mesh.normals_split_custom_set([(x,-z,y) for x,y,z in normals])
        obj_report[name] = {'seat_vertices':sum(map(len,groups)), 'minimum_cap_gap_m':min(gaps)}
    if write:
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
    return obj_report


if __name__ == '__main__':
    write = '--write' in sys.argv
    if '--source' in sys.argv:
        report = {'source':source(write)}
    else:
        report = {name:glb(ROOT/'battlebots/assets/models/atlas_runtime'/name,write)
                  for name in ['atlas_mx.glb','atlas_drives.glb']}
    print(json.dumps(report,indent=2))
    if not write:
        assert all(r['minimum_cap_gap_m'] >= TERMINAL_SEAT_END_INSET-1e-6
                   for asset in report.values() for r in asset.values()), 'Coincident or insufficiently recessed hood caps'
        print('ATLAS HOOD CAPS PASS')
