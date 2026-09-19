"""Side-view attack inspection frames, one-shot movie and rear exhaust sizes."""
import bpy, os
from mathutils import Vector
ROOT=os.path.dirname(os.path.abspath(__file__))
scene=bpy.context.scene; root=bpy.data.objects['SawbladeTank_ROOT']; camera=scene.camera
scene.render.engine='BLENDER_EEVEE'; scene.eevee.taa_render_samples=48
scene.eevee.use_gtao=True; scene.eevee.gtao_distance=1; scene.eevee.gtao_factor=1.1
scene.render.resolution_x=1200; scene.render.resolution_y=900; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; camera.data.ortho_scale=4.1
def view(location,target):
    camera.location=location
    camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
def still(label,f):
    root.update_tag(); scene.frame_set(f); bpy.context.view_layer.update()
    scene.render.filepath=os.path.join(ROOT,'sawblade_tank_'+label+'.png')
    bpy.ops.render.render(write_still=True)
root['weapon']=1; root['drive']=0; root['armor_side']=1
root['armor_top']=1; root['armor_front']=1; root['armor_rear']=1; root['exhaust']=2
view((-6,-.20,1.65),(0,-.20,.88))
for label,f in [('hammer_ready',1),('hammer_impact',9),('hammer_return',23)]: still(label,f)
root['drive']=1; root['armor_side']=2
view((-3.7,4.7,2.5),(0,.15,.84)); still('hammer_impact_armored_wheels',9)
root['drive']=0; root['armor_side']=1
view((-6,-.20,1.65),(0,-.20,.88))
scene.render.resolution_x=800; scene.render.resolution_y=600
scene.eevee.taa_render_samples=24
scene.render.image_settings.file_format='FFMPEG'; scene.render.ffmpeg.format='MPEG4'
scene.render.ffmpeg.codec='H264'; scene.render.ffmpeg.constant_rate_factor='MEDIUM'
scene.render.fps=30; scene.frame_start=1; scene.frame_end=33; scene.frame_step=1
scene.render.filepath=os.path.join(ROOT,'sawblade_tank_hammer_attack.mp4')
root.update_tag(); bpy.ops.render.render(animation=True)
scene.render.image_settings.file_format='PNG'
scene.render.resolution_x=1200; scene.render.resolution_y=900; scene.eevee.taa_render_samples=48
root['weapon']=0; root['armor_side']=1
view((-3.4,-4.7,2.1),(0,-.30,.85))
for choice,label in [(1,'small'),(2,'medium'),(3,'large')]:
    root['exhaust']=choice; still('exhaust_'+label,1)
print('ATTACK_AND_EXHAUST_PREVIEWS_COMPLETE',flush=True)
