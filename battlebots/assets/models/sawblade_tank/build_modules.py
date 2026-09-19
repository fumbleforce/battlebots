"""Authored interchangeable Blender modules, invoked before atlas preparation."""
module_records=[]; sockets={}
socket_positions={
    'weapon':(0,.30,.65), 'drive':(0,0,.30), 'armor_side':(0,0,.44),
    'armor_top':(0,0,1.04), 'armor_front':(0,.72,.32),
    'armor_rear':(0,-1.33,1.05), 'exhaust':(0,-1.36,.55),
}
for key,position in socket_positions.items():
    socket=empty('Socket_'+key,position); socket.parent=root
    socket.empty_display_type='ARROWS'; socket.empty_display_size=.12
    sockets[key]=socket
bpy.context.view_layer.update()

def module(name,slot,choice,objects):
    collection=bpy.data.collections.new(name); bot.children.link(collection)
    holder=empty('Module_'+name); holder.parent=sockets[slot]; holder.location=(0,0,0)
    holder['module_id']=name; holder['mount_socket']='Socket_'+slot
    bpy.context.view_layer.update()
    for obj in objects:
        if obj.parent not in objects: parent_keep(obj,holder)
    for obj in list(objects)+[holder]:
        for old in list(obj.users_collection): old.objects.unlink(obj)
        collection.objects.link(obj)
        obj['module_slot']=slot; obj['module_choice']=choice
    module_records.append({'id':name,'slot':slot,'choice':choice,'root':holder.name,'collection':collection.name})
    return holder

exec(compile(open(os.path.join(ROOT,'build_mechanics.py')).read(),'build_mechanics.py','exec'))

side_prefixes=('Tapered side service','Service cover','Recessed rectangular','Service plate bolt')
stock_side={obj for obj in drive_objects if obj.name.startswith(side_prefixes)}
module('weapon_saw','weapon',0,weapon_objects)
module('drive_tracks','drive',0,drive_objects-stock_side)
module('armor_side_reference','armor_side',1,stock_side)

# Complete hammer module includes its own baked actuator motion.
module('weapon_hammer','weapon',1,build_hammer())

before=set(bot.all_objects)
plate('Full width ramp shell',0,[(.30,.22),(1.60,.055),(1.60,.105),(.37,.75),(.26,.64)],1.46,yellow,bevel=.014)
bar('Ramp wear face',(0,.39,.752),(0,1.55,.137),1.24,.024,dark)
box('Ramp sharpened leading lip',(0,1.58,.086),(1.49,.10,.055),steel,.006)
cyl('Ramp hinge axle',(0,.30,.36),.085,1.55,dark,verts=24)
for x in [-.52,.52]:
    bar('Ramp top reinforcement',(x,.42,.745),(x,1.49,.178),.06,.042,yellow)
    cyl('Ramp hinge lock',(x,.30,.36),.11,.06,steel,verts=12)
for x in [-.35,.35]:
    bar('Ramp rigid chassis brace',(x,-.32,.58),(x,.32,.39),.075,.085,dark)
    cyl('Ramp capped hydraulic port',(x,-.39,.79),.031,.035,steel,'Y',6)
module('weapon_ramp','weapon',2,set(bot.all_objects)-before)

# Complete four-wheel drive package: no belts or track-specific frame survives.
before=set(bot.all_objects)
for x in [-.67,.67]:
    sign=1 if x>0 else -1
    for y in [-.55,.55]:
        wheel=empty('Wheel_SPIN_X',(x,y,.30)); parts=[]
        parts.append(cyl('All terrain tire',(x,y,.30),.28,.28,rubber,verts=24,bevel=.022))
        parts.append(cyl('Wheel steel rim',(x+sign*.15,y,.30),.205,.03,yellow,verts=16,bevel=.009))
        parts.append(cyl('Wheel axle cap',(x+sign*.18,y,.30),.066,.045,dark,verts=8))
        for j in range(16):
            q=j*2*pi/16
            ob=box('Tire tread block',(x,y+.275*cos(q),.30+.275*sin(q)),(.29,.075,.022),dark,.006)
            ob.rotation_euler.x=q-pi/2; parts.append(ob)
        bpy.context.view_layer.update()
        for obj in parts: parent_keep(obj,wheel)
        for f in [1,121]:
            wheel.rotation_euler.x=-(f-1)/120*4*pi
            wheel.keyframe_insert(data_path='rotation_euler',frame=f)
        linear(wheel)
        bar('Wheel suspension arm',(x-sign*.24,y-.10,.47),(x,y,.30),.075,.085,dark)
module('drive_wheels','drive',1,set(bot.all_objects)-before)

before=set(bot.all_objects)
for x in [-.89,.89]:
    plate('Heavy side skirt',x,[(-.80,.20),(.81,.20),(.84,.62),(.63,.75),(-.58,.58),(-.80,.46)],.052,yellow)
    sign=1 if x>0 else -1
    for y,z in [(-.64,.33),(.67,.37),(.41,.65)]: cyl('Skirt mounting bolt',(x+sign*.035,y,z),.024,.015,dark,verts=6)
    box('Over wheel armor fender',(x-sign*.16,.02,.725),(.40,1.37,.06),dark,.016)
module('armor_side_heavy','armor_side',2,set(bot.all_objects)-before)

before=set(bot.all_objects)
box('Top machinery guard rear',(0,-.07,1.06),(.95,.43,.06),yellow,.012)
for x in [-.3625,.3625]: box('Top guard notch wing',(x,.215,1.06),(.225,.14,.06),yellow,.012)
for x in [-.41,.41]: box('Top guard stand off',(x,-.03,.93),(.065,.42,.23),dark,.014)
for x in [-.27,0,.27]: box('Top armor cooling slot',(x,-.04,1.095),(.09,.26,.005),black,.005)
module('armor_top_guard','armor_top',1,set(bot.all_objects)-before)

before=set(bot.all_objects)
plate('Front chin armor',.745,[(-.54,.21),(.54,.21),(.50,.47),(.36,.54),(-.36,.54),(-.50,.47)],.07,yellow,'Y',.012)
for x in [-.39,.39]: cyl('Front guard bolt',(x,.789,.35),.026,.016,dark,'Y',6)
module('armor_front_guard','armor_front',1,set(bot.all_objects)-before)

before=set(bot.all_objects)
plate('Rear pack armor',-1.34,[(-.58,.64),(-.48,.56),(.48,.56),(.58,.64),(.58,1.45),(.48,1.55),(-.48,1.55),(-.58,1.45)],.075,yellow,'Y',.012)
box('Rear armor center band',(0,-1.383,1.05),(.19,.008,.96),black,.002)
for x in [-.44,.44]:
    for z in [.70,1.42]: cyl('Rear armor bolt',(x,-1.388,z),.024,.014,dark,'Y',6)
module('armor_rear_guard','armor_rear',1,set(bot.all_objects)-before)

def pipe(name,x,y,z,length,radius):
    vv=[]; ff=[]; steps=24
    for rr,yy in [(radius,y),(radius,y-length),(radius*.72,y-length),(radius*.72,y)]:
        for j in range(steps):
            q=j*2*pi/steps; vv.append((x+rr*cos(q),yy,z+rr*sin(q)))
    for k in range(4):
        for j in range(steps): ff.append((k*steps+j,k*steps+(j+1)%steps,((k+1)%4)*steps+(j+1)%steps,((k+1)%4)*steps+j))
    mm=bpy.data.meshes.new(name); mm.from_pydata(vv,[],ff); mm.update()
    ob=bpy.data.objects.new(name,mm); bot.objects.link(ob); finish(ob,name,steel)
    ob.data.materials.append(black)
    for face in ob.data.polygons:
        if face.index//steps==2: face.material_index=1

for choice,label,xs,length,radius in [(1,'small',[0],.25,.05),(2,'medium',[-.23,.23],.40,.068),(3,'large',[-.34,.34],.60,.095)]:
    before=set(bot.all_objects)
    box('Exhaust manifold '+label,(0,-1.47,.68),(.88,.14,.22),dark,.018)
    for x in [-.30,.30]:
        bar('Exhaust supported chassis bracket '+label,(x,-1.20,.47),(x,-1.47,.47),.055,.06,dark)
        bar('Exhaust manifold support '+label,(x,-1.47,.47),(x,-1.47,.66),.055,.06,dark)
    for x in xs:
        pipe('Horizontal hollow exhaust '+label,x,-1.50,.68,length,radius)
        cyl('Exhaust sleeve '+label,(x,-1.565,.68),radius*1.25,.13,dark,'Y',16)
        for yy in [-1.52,-1.615]: cyl('Exhaust clamp '+label,(x,yy,.68),radius*1.32,.025,yellow,'Y',16)
    module('exhaust_'+label,'exhaust',choice,set(bot.all_objects)-before)

# Socket roots stay in the chassis; every interchangeable object has a stable ID.
for obj in bot.objects:
    if obj!=root and obj.parent is None: parent_keep(obj,root)
