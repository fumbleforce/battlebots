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

side_prefixes=('Tapered side service','Service cover','Recessed rectangular','Service plate bolt')
stock_side={obj for obj in drive_objects if obj.name.startswith(side_prefixes)}
module('weapon_saw','weapon',0,weapon_objects)
module('drive_tracks','drive',0,drive_objects-stock_side)
module('armor_side_reference','armor_side',1,stock_side)

# Hammer attachment uses the same front mounting socket as the complete saw arm.
before=set(bot.all_objects)
for x in [-.27,.27]:
    box('Hammer mounting clevis',(x,.29,.74),(.14,.27,.29),yellow,.025)
cyl('Hammer pivot shaft',(0,.29,.86),.083,.77,dark,verts=24)
pivot=empty('Hammer_SWING_X',(0,.29,.86)); moving_start=set(bot.all_objects)
for x in [-.13,.13]:
    bar('Hammer forged arm',(x,.29,.86),(x,1.19,1.47),.09,.14,dark)
    bar('Hammer arm reinforcement',(x,.33,.90),(x,.93,1.32),.095,.055,yellow)
box('Hammer impact head',(0,1.22,1.49),(.80,.36,.35),dark,.045)
box('Hammer hardened striking face',(0,1.22,1.30),(.82,.38,.055),steel,.008)
for x in [-.27,.27]:
    box('Hammer yellow head strap',(x,1.22,1.50),(.10,.38,.36),yellow,.010)
    cyl('Hammer strap fastener',(x,1.416,1.50),.029,.014,steel,'Y',6)
bpy.context.view_layer.update()
for obj in set(bot.all_objects)-moving_start: parent_keep(obj,pivot)
module('weapon_hammer','weapon',1,set(bot.all_objects)-before)

before=set(bot.all_objects)
plate('Full width ramp shell',0,[(.30,.22),(1.60,.055),(1.60,.105),(.37,.75),(.26,.64)],1.46,yellow,bevel=.014)
bar('Ramp wear face',(0,.39,.752),(0,1.55,.137),1.24,.024,dark)
box('Ramp sharpened leading lip',(0,1.58,.086),(1.49,.10,.055),steel,.006)
cyl('Ramp hinge axle',(0,.30,.36),.085,1.55,dark,verts=24)
for x in [-.52,.52]:
    bar('Ramp top reinforcement',(x,.42,.745),(x,1.49,.178),.06,.042,yellow)
    cyl('Ramp hinge lock',(x,.30,.36),.11,.06,steel,verts=12)
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
box('Top machinery guard',(0,.0,1.06),(.95,.57,.06),yellow,.035)
for x in [-.41,.41]: box('Top guard stand off',(x,-.03,.93),(.065,.42,.23),dark,.014)
for x in [-.27,0,.27]: box('Top armor cooling slot',(x,0,1.095),(.09,.31,.005),black,.005)
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

def pipe(name,x,y,bottom,top,radius):
    vv=[]; ff=[]; steps=24
    for rr,z in [(radius,bottom),(radius,top),(radius*.72,top),(radius*.72,bottom)]:
        for j in range(steps):
            q=j*2*pi/steps; vv.append((x+rr*cos(q),y+rr*sin(q),z))
    for k in range(4):
        for j in range(steps): ff.append((k*steps+j,k*steps+(j+1)%steps,((k+1)%4)*steps+(j+1)%steps,((k+1)%4)*steps+j))
    mm=bpy.data.meshes.new(name); mm.from_pydata(vv,[],ff); mm.update()
    ob=bpy.data.objects.new(name,mm); bot.objects.link(ob); finish(ob,name,steel)
    ob.data.materials.append(black)
    for face in ob.data.polygons:
        if face.index//steps==2: face.material_index=1

for choice,label,xs,height,radius in [(1,'small',[0],1.15,.05),(2,'medium',[-.23,.23],1.49,.068),(3,'large',[-.34,.34],1.88,.095)]:
    before=set(bot.all_objects)
    box('Exhaust manifold '+label,(0,-1.40,.57),(.76,.14,.15),dark,.025)
    for x in xs:
        pipe('Hollow exhaust stack '+label,x,-1.45,.60,height,radius)
        cyl('Exhaust sleeve '+label,(x,-1.45,.78),radius*1.25,.30,dark,'Z',16)
        for z in [.65,.91]: cyl('Exhaust clamp '+label,(x,-1.45,z),radius*1.32,.025,yellow,'Z',16)
    module('exhaust_'+label,'exhaust',choice,set(bot.all_objects)-before)

# Socket roots stay in the chassis; every interchangeable object has a stable ID.
for obj in bot.objects:
    if obj!=root and obj.parent is None: parent_keep(obj,root)
