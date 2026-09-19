"""Render body-focused side and rear views without altering the saved source."""
import bpy, os
from mathutils import Vector
ROOT=os.path.dirname(os.path.abspath(__file__))
scene=bpy.context.scene; scene.frame_set(1)
scene.render.engine='BLENDER_EEVEE'; scene.eevee.taa_render_samples=64
scene.eevee.use_gtao=True; scene.eevee.gtao_distance=2; scene.eevee.gtao_factor=1.15
scene.render.resolution_x=1200; scene.render.resolution_y=900; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
camera=scene.camera; camera.data.ortho_scale=3.85
for name,location,target in [
    ('rear',(-3.8,-4.7,2.7),(0,-.10,.82)),
    ('side',(-6,.10,1.0),(0,.10,.84)),
]:
    camera.location=location
    camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=os.path.join(ROOT,'sawblade_tank_'+name+'.png')
    bpy.ops.render.render(write_still=True)
