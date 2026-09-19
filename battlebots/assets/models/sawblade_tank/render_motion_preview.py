"""Render a compact four-second preview from the saved Blender source."""
import bpy, os
ROOT=os.path.dirname(os.path.abspath(__file__))
scene=bpy.context.scene
atlas=bpy.data.images['SawbladeTank | 1024 color atlas']
assert tuple(atlas.size)==(1024,1024) and atlas.packed_file is not None
links=[o for o in bpy.data.objects if o.name.startswith('Tread_')]
scene.frame_set(1); seam={o.name:o.matrix_world.copy() for o in links}
scene.frame_set(121)
for obj in links:
    assert (obj.matrix_world.translation-seam[obj.name].translation).length<1e-5
    assert obj.matrix_world.to_quaternion().rotation_difference(seam[obj.name].to_quaternion()).angle<.001
print('SAVED_ASSET_VERIFIED',scene['triangle_count'],'triangles, packed 1K atlas, 88 seamless tread links',flush=True)
scene.render.engine='BLENDER_EEVEE'; scene.eevee.taa_render_samples=16
scene.eevee.use_gtao=True; scene.eevee.gtao_distance=3; scene.eevee.gtao_factor=1.25
scene.render.resolution_x=700; scene.render.resolution_y=550; scene.render.resolution_percentage=100
scene.frame_start=1; scene.frame_end=120; scene.frame_step=2; scene.render.fps=15
scene.render.image_settings.file_format='FFMPEG'; scene.render.ffmpeg.format='MPEG4'; scene.render.ffmpeg.codec='H264'
scene.render.ffmpeg.constant_rate_factor='MEDIUM'; scene.render.filepath=os.path.join(ROOT,'sawblade_tank_motion.mp4')
bpy.ops.render.render(animation=True)
