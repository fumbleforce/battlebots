"""Connected weapon hydraulics and exportable, sampled hammer action."""
from mathutils import Matrix

def hose(name,points,radius=.012):
    curve=bpy.data.curves.new(name,'CURVE'); curve.dimensions='3D'
    curve.bevel_depth=radius; curve.bevel_resolution=1
    spline=curve.splines.new('BEZIER'); spline.bezier_points.add(len(points)-1)
    for bp,point in zip(spline.bezier_points,points):
        bp.co=point; bp.handle_left_type='AUTO'; bp.handle_right_type='AUTO'
    ob=bpy.data.objects.new(name,curve); bot.objects.link(ob); curve.materials.append(rubber)
    return ob

def pin(name,p,width=.15,eye_radius=.052):
    cyl(name+' rod end eye',p,eye_radius,.065,dark,verts=16)
    cyl(name+' transverse pin',p,.025,width,steel,verts=12)
    for dx in [-width/2,width/2]:
        cyl(name+' pin retainer',(p[0]+dx,p[1],p[2]),.034,.012,yellow,verts=6)

def clevis(name,p,foot):
    for dx in [-.059,.059]:
        a=Vector(foot)+Vector((dx,0,0)); b=Vector(p)+Vector((dx,0,0))
        bar(name+' clevis cheek',a,b,.027,.08,dark)
    box(name+' bracket foot',foot,(.16,.12,.045),dark,.006)

# Old ram props were common chassis geometry and some had unsupported ends.
# Replace the cylinders, keeping structural chassis gussets and track hangers.
remove_prefixes=('Transverse upper pivot','Upper shaft yellow','Rear mechanism clevis',
    'Rear triangular brace','Rear twin hinge','Pack mounting bolt','Diagonal lift ram',
    'Lift ram','Rectangular hydraulic','Main exposed','Rear hydraulic feed','Main ram',
    'Lower frame link','Cylinder mounting','Hydraulic jacket','Manifold return hose',
    'Upper diagonal linkage','Lower linkage','Central hydraulic','Black hydraulic hose')
for ob in list(bot.all_objects):
    if ob.name.startswith(remove_prefixes):
        weapon_objects.discard(ob); bpy.data.objects.remove(ob,do_unlink=True)
# Remove the old unsupported bolt pair at the rear of the saw module.
for ob in list(weapon_objects):
    if ob.name.startswith('Pivot') and ob.location.y<-.5:
        weapon_objects.remove(ob); bpy.data.objects.remove(ob,do_unlink=True)

new=set(bot.all_objects)
for x in [-.35,.35]:
    sign=1 if x>0 else -1
    for tag,a,b,r in [
        ('Saw lower',Vector((x,-.32,.745)),Vector((x,.48,.77)),.062),
        ('Saw upper',Vector((x,-.28,1.075)),Vector((x,.30,1.30)),.040),
    ]:
        direction=(b-a).normalized(); end=a+direction*((b-a).length*.57)
        rod(tag+' cylinder barrel',a,end,r,yellow)
        rod(tag+' polished piston',end-direction*.10,b,r*.46,chrome)
        rod(tag+' gland',end-direction*.025,end+direction*.015,r*1.15,dark)
        pin(tag+' chassis',a); pin(tag+' arm',b)
        clevis(tag+' chassis',a,(x,-.405,a.z-.13))
        # An outboard yoke bridges the X offset to the actual saw lift cheek.
        bar(tag+' outboard yoke',(sign*.23,b.y,b.z),b,.075,.085,dark)
        hose(tag+' flexible supply',[(x,-.395,a.z+.03),(x+sign*.095,-.37,a.z+.15),
             (x+sign*.09,a.y+.13,a.z+.15),(x,a.y+.12,a.z+.04)])
    # Central ram ends are pinned into the lift arm, not left beside it.
    a=Vector((sign*.23,-.28,.90)); b=Vector((sign*.23,.40,.90))
    rod('Saw central barrel',a,(a+b)/2,.047,dark)
    rod('Saw central piston',(a+b)/2-Vector((0,.08,0)),b,.022,chrome)
    pin('Saw central rear',a,.11); pin('Saw central forward',b,.11)
    clevis('Saw central rear',a,(a.x,-.405,.77))
weapon_objects.update(set(bot.all_objects)-new)

def build_hammer():
    global hammer_metadata
    start=set(bot.all_objects)
    p=Vector((0,.29,.86)); head_center=Vector((0,1.22,1.49))
    face_depth=.19+.055/2
    offset=head_center-p
    angle=math.asin((face_depth-p.z)/math.hypot(offset.y,offset.z))-math.atan2(offset.z,offset.y)
    for x in [-.27,.27]:
        box('Hammer mounting clevis',(x,.29,.74),(.14,.27,.29),yellow,.025)
    cyl('Hammer pivot shaft',p,.083,.87,dark,verts=24)
    hinge=empty('Hammer_SWING_X',p)
    moving=set(bot.all_objects)
    for x in [-.19,.19]:
        # Raised dogleg clears the chassis deck and optional front chin at impact.
        elbow=(x,.68,1.36)
        bar('Hammer forged lower arm',(x,.29,.86),elbow,.075,.11,dark)
        bar('Hammer forged upper arm',elbow,(x,1.19,1.47),.075,.11,dark)
        bar('Hammer arm reinforcement',(x,.38,1.00),(x,.67,1.35),.080,.045,yellow)
    for x in [-.35,.35]:
        bar('Hammer hinge crank',(x,.29,.86),(x,.47,.74),.075,.095,yellow)
        pin('Hammer crank',(x,.47,.74),width=.09,eye_radius=.040)
    bpy.context.view_layer.update()
    for ob in set(bot.all_objects)-moving: parent_keep(ob,hinge)
    head=empty('Hammer_HEAD_ALIGNMENT',head_center); headparts=set(bot.all_objects)
    box('Hammer impact head',head_center,(.80,.36,.35),dark,.045)
    box('Hammer hardened striking face',(0,1.22,1.30),(.82,.38,.055),steel,.008)
    for x in [-.27,.27]:
        box('Hammer yellow head strap',(x,1.22,1.50),(.10,.38,.36),yellow,.010)
        cyl('Hammer strap fastener',(x,1.416,1.50),.029,.014,steel,'Y',6)
    contact=empty('Hammer_Impact',(0,1.22,head_center.z-face_depth))
    contact.empty_display_type='ARROWS'; contact.empty_display_size=.12
    contact['presentation_only']=True
    bpy.context.view_layer.update()
    for ob in set(bot.all_objects)-headparts: parent_keep(ob,head)
    head.rotation_euler.x=-angle; bpy.context.view_layer.update(); parent_keep(head,hinge)

    actuators=[]
    for side,x in [('L',-.35),('R',.35)]:
        a=Vector((x,-.32,.745)); b=Vector((x,.47,.74)); d=(b-a).normalized()
        clevis('Hammer fixed '+side,a,(x,-.32,.575)); pin('Hammer fixed '+side,a)
        barrel=empty('Hammer_Cylinder_'+side,a); rodgroup=empty('Hammer_Rod_'+side,b)
        before=set(bot.all_objects)
        rod('Hammer yellow hydraulic barrel '+side,a+d*.025,a+d*.44,.062,yellow)
        rod('Hammer cylinder gland '+side,a+d*.405,a+d*.455,.066,dark)
        bpy.context.view_layer.update()
        for ob in set(bot.all_objects)-before: parent_keep(ob,barrel)
        # Swivel inlet at the fixed pin keeps both hose ends stationary.
        port=a+Vector((.085 if x>0 else -.085,0,0))
        rod('Hammer swivel hydraulic inlet '+side,a,port,.018,steel)
        hose('Hammer pressure hose '+side,[(x,-.39,.79),(port.x,-.39,.90),
              (port.x,-.30,.88),port])
        before=set(bot.all_objects)
        rod('Hammer telescoping chrome rod '+side,b-d*.49,b,.027,chrome)
        bpy.context.view_layer.update()
        for ob in set(bot.all_objects)-before: parent_keep(ob,rodgroup)
        actuators.append((barrel,rodgroup,a,b,d))

    def swing(frame):
        if frame<=9: return angle*((frame-1)/8)**2
        if frame<=12: return angle
        t=(frame-12)/21
        return angle*(1-(3*t*t-2*t*t*t))
    # Quarter-frame baking retains connected joints even between export frames.
    for i in range(129):
        frame=1+i/4; theta=swing(frame); rotation=Matrix.Rotation(theta,4,'X')
        hinge.rotation_euler.x=theta
        hinge.keyframe_insert(data_path='rotation_euler',frame=frame)
        for barrel,rodgroup,a,b,d in actuators:
            end=p+rotation@(b-p); direction=(end-a).normalized()
            q=d.rotation_difference(direction)
            barrel.rotation_mode='QUATERNION'; barrel.rotation_quaternion=q
            rodgroup.rotation_mode='QUATERNION'; rodgroup.rotation_quaternion=q
            rodgroup.location=end
            for ob in [barrel,rodgroup]:
                ob.keyframe_insert(data_path='location',frame=frame)
                ob.keyframe_insert(data_path='rotation_quaternion',frame=frame)
    channels=[hinge]+[ob for entry in actuators for ob in entry[:2]]
    for ob in channels:
        action=ob.animation_data.action
        action.name='hammer_attack' if ob==hinge else 'hammer_attack__'+ob.name
        action.use_fake_user=True
        for fc in action.fcurves:
            fc.extrapolation='CONSTANT'
            for key in fc.keyframe_points: key.interpolation='LINEAR'
        track=ob.animation_data.nla_tracks.new(); track.name='hammer_attack'
        strip=track.strips.new('hammer_attack',1,action); strip.extrapolation='HOLD'
        ob.animation_data.action=None
    bpy.context.scene.timeline_markers.new('Hammer impact | presentation only',frame=9)
    bpy.context.scene.frame_set(1); bpy.context.view_layer.update()
    hammer_metadata={'clip':'hammer_attack','fps':30,'frame_start':1,'frame_end':33,
        'duration_seconds':32/30,'impact_frame':9,'impact_time_seconds':8/30,
        'hold_end_frame':12,'loop':False,'pivot':'Hammer_SWING_X',
        'pivot_position':list(p),'contact_marker':'Hammer_Impact','swing_degrees':math.degrees(angle),
        'baked_objects':[ob.name for ob in channels],'bake_step_frames':.25,
        'nla_track':'hammer_attack','metadata_only':'Impact marker does not apply gameplay damage',
        'cylinder_barrel_length':.44,'cylinder_rod_length':.49,
        'chassis_anchors':[[-.35,-.32,.745],[.35,-.32,.745]],
        'moving_anchor_offset':[0,.18,-.12]}
    return set(bot.all_objects)-start
