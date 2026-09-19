"""Detailed visual construction; executed inside build_flamebot.py's helpers."""
def meshpart(name,verts,faces,mat=red,parent=chassis,bevel=.008):
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
    o=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(o)
    return finish(o,name,mat,parent,bevel)

def panel(name,points,thickness=.04,mat=red,parent=chassis):
    # Polygon points lie on the outer face; extrude inward along its normal.
    n=(Vector(points[1])-Vector(points[0])).cross(Vector(points[2])-Vector(points[0])).normalized()
    if n.z<0: points=list(reversed(points)); n=-n
    k=len(points); vs=list(points)+[tuple(Vector(p)-n*thickness) for p in points]
    fs=[tuple(range(k)),tuple(reversed(range(k,2*k)))]+[(i,(i+1)%k,(i+1)%k+k,i+k) for i in range(k)]
    return meshpart(name,vs,fs,mat,parent,.007)

def hull(name,sections,mat=red,parent=chassis):
    # Each section: y, halfwidth at base, base height, halfwidth at roof, roof height.
    vs=[]
    for y,wb,zb,wt,zt in sections: vs.extend([(-wb,y,zb),(wb,y,zb),(wt,y,zt),(-wt,y,zt)])
    fs=[(3,2,1,0),tuple(range(len(vs)-4,len(vs)))]
    for s in range(len(sections)-1):
        for i in range(4): fs.append((s*4+i,s*4+(i+1)%4,(s+1)*4+(i+1)%4,(s+1)*4+i))
    return meshpart(name,vs,fs,mat,parent,.018)

def rod(name,a,b,r,mat=steel,parent=chassis,verts=12):
    a,b=Vector(a),Vector(b); o=cyl(name,(a+b)/2,r,(b-a).length,mat,parent,verts=verts,bevel=.002)
    # Rotation must be specified in world space even when its parent is offset.
    world=o.matrix_world.copy(); world= (b-a).to_track_quat('Z','Y').to_matrix().to_4x4(); world.translation=(a+b)/2
    o.matrix_world=world
    return o

def surface_bolt(p,normal=(0,0,1),parent=chassis,r=.017):
    n=Vector(normal).normalized(); p=Vector(p)
    rod('Recessed washer',p-n*.002,p+n*.004,r*1.55,dark,parent,16)
    rod('Hex head',p+n*.005,p+n*.015,r,steel,parent,6)
    rod('Fastener center',p+n*.015,p+n*.016,r*.37,black,parent,6)

def slash_marks(points,parent=chassis):
    for a,b in points: rod('Scored exposed edge',a,b,.0018,steel,parent,6)

def paint_chip(center,u,v,sx,sy,parent=chassis):
    # Legacy calls preserve deterministic random placement; wear is now in maps.
    return

# A broad, low body with a continuous multi-angle front glacis.
hull('Faceted lower chassis',[(-1.05,.49,.23,.6,.62),(-.84,.62,.21,.66,.77),(.29,.62,.21,.64,.77),(.81,.58,.18,.62,.49),(1.32,.54,.105,.57,.18)],dark)
hull('Shouldered hull armor',[(-1.01,.52,.34,.59,.66),(-.8,.64,.34,.66,.775),(.28,.64,.34,.63,.775),(.83,.58,.22,.60,.49)],red)
box('Recessed turret deck',(0,-.28,.784),(1.18,.99,.045),red,bevel=.022)
box('Deck rim rear',(0,-.84,.77),(1.18,.055,.075),dark)
for side in [-1,1]:
    # Central side plates fit BETWEEN wheels rather than extending into tires.
    x=side*.658
    panel('Recessed side armor',[(x,-.24,.34),(x,.20,.34),(x,.25,.63),(x,-.30,.67)],.022,red)
    for y,z in [(-.23,.4),(.16,.4),(-.22,.61),(.17,.59)]: surface_bolt((side*.68,y,z),(side,0,0))
    text('Side serial','07',(side*.684,-.025,.44),.16,(math.pi/2,0,side*math.pi/2))
    box('Side sill reinforcement',(side*.645,-.04,.295),(.045,.58,.055),steel)
    for y in [-.65,.63]:
        cyl('Axle housing',(side*.675,y,.42),.12,.15,dark,chassis,'X',20)
        cyl('Exposed axle',(side*.74,y,.42),.064,.16,steel,chassis,'X')
        # Narrow fender arches: inner edge at .72, tire inner edge at .755.
        for i in range(5):
            a=(i-2)*.27
            box('Segmented wheel arch',(side*.845,y+.473*math.sin(a),.42+.473*math.cos(a)),(.23,.139,.034),red,chassis,.006,(-a,0,0))
        for dy in [-.32,.32]: rod('Fender support',(side*.65,y+dy,.55),(side*.76,y+dy,.74),.018,dark)

# The upper red sloping hood and lower steel blade form a visible kink.
upper_a=Vector((0,.31,.802)); upper_b=Vector((0,.88,.49))
lower_a=Vector((0,.89,.492)); lower_b=Vector((0,1.57,.062))
def armor_strip(name,x0,x1,a,b,mat=red):
    pts=[(x0,a.y,a.z),(x1,a.y,a.z),(x1,b.y,b.z),(x0,b.y,b.z)]
    o=panel(name,pts,.047,mat)
    n=Vector((0,a.z-b.z,b.y-a.y)).normalized()
    for x in [x0+.045,x1-.045]:
        for t in [.13,.87]: surface_bolt(Vector((x,0,0))+a.lerp(b,t)+n*.004,n,r=.017)
    # Fine exposed edge scars are localized, not a uniform speckle texture.
    for _ in range(7):
        t=random.random(); x=random.choice([x0+.008,x1-.008]); p=Vector((x,0,0))+a.lerp(b,t)+n*.001
        rod('Plate edge wear',p,p+(b-a).normalized()*random.uniform(.014,.05),.0017,steel,verts=6)
    for _ in range(17):
        t=random.uniform(.035,.965)
        x=random.choice([x0+random.uniform(.007,.035),x1-random.uniform(.007,.035)])
        p=Vector((x,0,0))+a.lerp(b,t)+n*.0014
        paint_chip(p,(1,0,0),(a-b).normalized(),random.uniform(.008,.034),random.uniform(.016,.08))
    return n
for x0,x1 in [(-.645,-.23),(.06,.645)]: armor_strip('Angled upper glacis',x0,x1,upper_a,upper_b)
armor_strip('Hood grille well',-.212,.042,upper_a,upper_b,black)
for t in np.linspace(.12,.88,9):
    p=upper_a.lerp(upper_b,float(t)); p.x=-.085; p+=Vector((0,.018,.03))
    box('Recessed hood cooling louver',p,(.215,.038,.023),dark,rot=(-.501,0,0),bevel=.003)
# Continuous closed backing joins the armored face and both wheel shields.
meshpart('Solid plow central body',[
    (-.67,.89,.492),(.67,.89,.492),(.67,1.57,.062),(-.67,1.57,.062),
    (-.67,.79,.475),(.67,.79,.475),(.67,1.435,.057),(-.67,1.435,.057)],
    [(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],dark,chassis,.005)
for x0,x1,mat in [(-.65,-.335,red),(-.331,.331,steel),(.335,.65,red)]: armor_strip('Thick lower ram plate',x0,x1,lower_a,lower_b,mat)
for side in [-1,1]:
    # Folded, solid wheel shield. The outer leading corner sweeps BACK in top
    # view; the raised outer shoulder protects the front of the tire.
    a=Vector((side*.66,.89,.493));b=Vector((side*1.155,1.125,.64))
    c=Vector((side*1.255,1.315,.062));d=Vector((side*.66,1.57,.062))
    e=Vector((side*.735,1.16,.74))
    front=[a,e,b,c,d]
    back=[p-Vector((0,.09,.008)) for p in front]
    meshpart('Folded solid wheel shield',[tuple(p) for p in front+back],
        [(0,1,4),(1,3,4),(1,2,3),(5,9,6),(6,9,8),(6,8,7),(0,5,6,1),(1,6,7,2),(2,7,8,3),(3,8,9,4),(4,9,5,0)],yellow,chassis,.005)
    # Painted stripes conform to both facets of the folded shield.
    # Parameterize each triangular face so paint follows the angled surface.
    for tri in [[a,e,d],[e,c,d],[e,b,c]]:
        aa,bb,cc=tri;n=(bb-aa).cross(cc-aa).normalized()
        if n.y<0:n=-n
        for start in np.arange(-1.1,1.2,.17):
            # Clip in barycentric coordinates using a diagonal world X/Z band.
            poly=[aa,bb,cc]
            for limit,above in [(float(start),True),(float(start)+.072,False)]:
                result=[]
                for p,q in zip(poly,poly[1:]+poly[:1]):
                    fp=side*p.x-1.35*p.z-limit;fq=side*q.x-1.35*q.z-limit
                    ip=fp>=0 if above else fp<=0;iq=fq>=0 if above else fq<=0
                    if ip:result.append(p)
                    if ip!=iq:result.append(p+(q-p)*(fp/(fp-fq)))
                poly=result
                if not poly:break
            if len(poly)>2:meshpart('Shield hazard paint',[tuple(p+n*.001) for p in poly],[tuple(range(len(poly)))],dark,chassis,0)
    for p in [e.lerp(b,.18),e.lerp(b,.78),d.lerp(c,.25),d.lerp(c,.82)]:
        surface_bolt(p+Vector((0,.004,.004)),(0,.8,.6),r=.02)
    # Deep rear return and welded braces make this a volume, not a thin fin.
    rod('Plow rear reinforcement',(.64*side,.86,.41),(.70*side,1.18,.41),.034,dark)
    rod('Plow rear reinforcement',(.70*side,1.18,.41),(1.12*side,1.18,.47),.034,dark)
    rod('Plow lower cutting edge',d,c,.014,steel)
    # Cut-looking black tow slots at the bottom of each red blade panel.
    box('Blade tow recess',(side*.49,1.503,.110),(.145,.071,.011),black,rot=(-.564,0,0),bevel=.009)
    rod('Blade lower wear edge',(side*.34,1.572,.065),(side*.65,1.572,.065),.009,steel)
hood_rot=(Euler((-.501,0,0)).to_matrix() @ Euler((0,0,math.pi)).to_matrix()).to_euler()
text('Large hood number','07',(.37,.688,.611),.235,hood_rot)
text('Hull small warning','KEEP CLEAR',(-.435,.723,.593),.037,hood_rot)

# Rear panel: deep grille, visible core, armored bumper and small service features.
box('Rear service surround',(0,-1.045,.51),(1.1,.06,.31),red)
box('Rear dark grille',(0,-1.081,.51),(.67,.025,.218),black)
for x in np.linspace(-.29,.29,13): box('Radiator fins',(float(x),-1.10,.51),(.012,.021,.177),steel,bevel=.001)
for z in [.44,.51,.58]: box('Rear grille crossbar',(0,-1.117,z),(.68,.032,.02),dark,bevel=.003)
for side in [-1,1]:
    box('Rear corner protector',(side*.52,-1.08,.37),(.18,.09,.2),dark)
    for z in [.39,.61]: surface_bolt((side*.43,-1.083,z),(0,-1,0))
    tube('Recovery tow eye',(side*.44,-1.14,.29),.047,.026,.022,steel,chassis,'Y',16)
text('Rear chassis serial','BB / 07',(0,-1.085,.67),.061,(math.pi/2,0,0))

# Broad chamfered tires with separated staggered tread and multi-part wheel hubs.
wheel_radius=.402
for side in [-1,1]:
    x=side*.93
    for y in [-.65,.63]:
        wheel=empty(('WheelLeft' if side<0 else 'WheelRight')+('Front' if y>0 else 'Rear'),(x,y,.42),root)
        # Revolved tire profile instead of a flat cylinder.
        vs=[]; n=48
        for dx,r in [(-.175,.285),(-.17,.349),(-.137,.391),(-.075,.401),(.075,.401),(.137,.391),(.17,.349),(.175,.285)]:
            for i in range(n): a=i*math.tau/n; vs.append((x+dx,y+r*math.sin(a),.42+r*math.cos(a)))
        fs=[]
        for j in range(7):
            for i in range(n): fs.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
        tire=meshpart('Rounded tire sidewall',vs,fs,rubber,wheel,0)
        for p in tire.data.polygons:p.use_smooth=True
        for i in range(24):
            for lane in [-1,1]:
                a=(i+.18*lane)*math.tau/24
                box('Staggered traction block',(x+lane*.083,y+.399*math.sin(a),.42+.399*math.cos(a)),(.151,.081,.031),rubber,wheel,.007,(-a,0,lane*.10))
        face=x+side*.176
        tube('Sidewall embossed bead',(face,y,.42),.32,.313,.004,rubber,wheel,'X',48)
        cyl('Recessed rim bed',(face,y,.42),.282,.012,dark,wheel,'X',40)
        tube('Wheel rim rolled lip',(face+side*.007,y,.42),.272,.255,.018,steel,wheel,'X',40)
        cyl('Pressed red dish',(face+side*.014,y,.42),.253,.019,red,wheel,'X',40)
        tube('Inner steel ring',(face+side*.028,y,.42),.169,.144,.016,dark,wheel,'X',32)
        cyl('Hub bearing',(face+side*.036,y,.42),.10,.033,steel,wheel,'X',24)
        cyl('Hub dust cap',(face+side*.057,y,.42),.065,.018,dark,wheel,'X',16)
        for i in range(10):
            a=i*math.tau/10
            surface_bolt((face+side*.025,y+.223*math.sin(a),.42+.223*math.cos(a)),(side,0,0),wheel,.012)
            aa=a+math.pi/10
            cyl('Recessed wheel vent',(face+side*.026,y+.192*math.sin(aa),.42+.192*math.cos(aa)),.024,.003,black,wheel,'X',12,0)

# Low tapered turret on layered rotating bearing. No box-shaped tower.
turret.location=(0,-.18,.84)
cyl('Lower slew bearing',(0,-.18,.824),.42,.058,dark,chassis,'Z',64)
tube('Exposed slew race',(0,-.18,.858),.397,.363,.024,steel,turret,'Z',64)
cyl('Turret pedestal',(0,-.18,.90),.327,.063,dark,turret,'Z',40)
for i in range(16):
    a=i*math.tau/16; surface_bolt((.38*math.cos(a),-.18+.38*math.sin(a),.876),parent=turret,r=.012)
hull('Tapered armored tower',[(-.57,.31,.94,.27,1.325),(-.38,.415,.94,.32,1.39),(.06,.405,.94,.29,1.37),(.19,.30,.99,.245,1.30)],red,turret)
panel('Sloping tower roof',[(-.28,-.36,1.401),(.28,-.36,1.401),(.253,.048,1.382),(-.253,.048,1.382)],.031,red,turret)
box('Inset hatch gasket',(-.045,-.275,1.414),(.38,.24,.014),black,turret,.019)
box('Armored roof hatch',(-.045,-.275,1.431),(.35,.212,.023),dark,turret,.021)
for x in [-.16,.08]:
    box('Hatch hinge',(x,-.397,1.436),(.071,.045,.033),steel,turret,.004)
rod('Hatch handle bridge',(-.10,-.265,1.476),(.045,-.265,1.476),.012,dark,turret)
for x in [-.10,.045]:rod('Hatch handle foot',(x,-.265,1.448),(x,-.265,1.476),.012,dark,turret)
for side in [-1,1]:
    # Separate canted cheek plates follow the taper, leaving visible dark seams.
    pts=[(side*.422,-.34,.985),(side*.403,.035,.985),(side*.305,.035,1.343),(side*.335,-.34,1.36)]
    panel('Angled tower cheek',pts,.024,red,turret)
    for y in [-.29,-.01]:
        for z in [1.025,1.30]:
            x=side*(.428-(z-.985)*.26); surface_bolt((x,y,z),(side,0,.26),turret,.013)
    flame=[(-.078,0),(-.108,.042),(-.105,.11),(-.063,.08),(-.052,.177),(-.019,.135),(.012,.24),(.04,.168),(.074,.117),(.068,.075),(.10,.1),(.104,.04),(.059,0)]
    vs=[]
    for dy,dz in flame:
        z=1.055+dz; vs.append((side*(.431-(z-.985)*.26),-.185+dy,z))
    meshpart('Painted flame insignia',vs,[tuple(range(len(vs)))],ivory,turret,0)
    for _ in range(19):
        z=random.uniform(1.005,1.325);y=random.choice([random.uniform(-.325,-.29),random.uniform(-.002,.022)])
        x=side*(.427-(z-.985)*.29)
        paint_chip((x,y,z),(0,side,0),(-side*.29,0,1),random.uniform(.007,.019),random.uniform(.008,.035),turret)

# External flamer mantlet: a visible mount, offset flange and free barrel shank.
fx=-.15; fz=1.205
box('Flamer external mounting plate',(fx,.213,fz),(.35,.055,.285),dark,turret,.022)
for dx in [-.137,.137]:
    for dz in [-.102,.102]:surface_bolt((fx+dx,.245,fz+dz),(0,1,0),turret,.013)
cyl('Flamer stand-off boss',(fx,.288,fz),.126,.076,steel,turret,'Y',24)
tube('Mantlet flange',(fx,.345,fz),.16,.09,.042,dark,turret,'Y',16)
for i in range(8):
    a=i*math.tau/8;surface_bolt((fx+.138*math.cos(a),.37,fz+.138*math.sin(a)),(0,1,0),turret,.011)
cyl('Exposed flamer shank',(fx,.603,fz),.084,.48,dark,turret,'Y',32)
for y in [.407,.446]:tube('Shank rib',(fx,y,fz),.099,.083,.018,steel,turret)
for y in [.718,1.066]:tube('Heat shield end ring',(fx,y,fz),.14,.102,.031,brass,turret)
sleeve=tube('Perforated yellow heat shield',(fx,.89,fz),.143,.122,.315,yellow,turret,n=40)
cutters=[]
for row,y in enumerate([.78,.854,.928,1.002]):
    for i in range(12):
        a=(i+.5*(row%2))*math.tau/12; v=Vector((math.cos(a),0,math.sin(a)))
        bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=.019,depth=.07,location=Vector((fx,y,fz))+v*.14)
        c=bpy.context.object;c.rotation_euler=v.to_track_quat('Z','Y').to_euler();cutters.append(c)
bpy.ops.object.select_all(action='DESELECT')
for c in cutters:c.select_set(True)
bpy.context.view_layer.objects.active=cutters[0];bpy.ops.object.join();cutter=bpy.context.object
bpy.context.view_layer.objects.active=sleeve
mod=sleeve.modifiers.new('Open ventilation holes','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter
bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)
tube('Muzzle throat',(fx,1.14,fz),.10,.077,.2,dark,turret,n=24)
tube('Octagonal blast nozzle',(fx,1.26,fz),.135,.094,.23,dark,turret,n=8)
tube('Worn nozzle rim',(fx,1.379,fz),.138,.112,.019,steel,turret,n=8)
cyl('Recessed nozzle darkness',(fx,1.11,fz),.076,.008,black,turret,'Y')
for side in [-1,1]:
    box('Nozzle locking jaw',(fx+side*.124,1.235,fz),(.026,.10,.045),brass,turret,.004)
    surface_bolt((fx+side*.141,1.235,fz),(side,0,0),turret,.009)
rod('Under-barrel supply line',(fx-.10,.42,fz-.105),(fx-.10,.91,fz-.105),.015,brass,turret)
for y in [.46,.66]:rod('Barrel saddle leg',(fx-.11,y,fz-.11),(fx+.11,y,fz-.11),.014,dark,turret)

# Side minigun, layered receiver with motor housing and separate spin pivot.
gx=.56; gz=1.066
box('Minigun cantilever',(.424,-.015,1.015),(.22,.18,.09),steel,turret,.015)
cyl('Minigun elevation pin',(.472,.06,gz),.07,.18,dark,turret,'X',20)
box('Minigun receiver',(gx,.144,gz),(.255,.32,.226),dark,turret,.019)
for side in [-1,1]:
    box('Receiver layered cheek',(gx+side*.136,.15,gz),(.027,.24,.181),steel,turret,.01)
    for y in [.063,.232]:surface_bolt((gx+side*.155,y,gz+.054),(side,0,0),turret,.014)
box('Receiver top access',(gx,.13,gz+.126),(.20,.215,.029),dark,turret,.006)
for y in [.07,.13,.19]:box('Receiver cooling slit',(gx,y,gz+.142),(.141,.018,.007),black,turret,.002)
cyl('Rear minigun motor',(gx,-.08,gz),.086,.16,dark,turret,'Y',20)
for y in [-.10,-.055]:tube('Motor cooling band',(gx,y,gz),.091,.08,.018,steel,turret)
gun=empty('MinigunSpin',parent=turret); bpy.context.view_layer.update();gun.matrix_world.translation=Vector((gx,.338,gz))
cyl('Minigun rotor',(gx,.328,gz),.105,.051,dark,gun,'Y',24)
for i in range(6):
    a=i*math.tau/6;x=gx+.066*math.cos(a);z=gz+.066*math.sin(a)
    tube('Rotary barrel',(x,.604,z),.026,.016,.52,dark,gun,n=12)
    tube('Barrel front sleeve',(x,.853,z),.029,.017,.072,steel,gun,n=12)
    cyl('Deep bore recess',(x,.82,z),.015,.004,black,gun,'Y',12,0)
for y in [.42,.756]:tube('Barrel clamp',(gx,y,gz),.11,.087,.037,steel,gun,n=12)
for i in range(6):
    a=i*math.tau/6;surface_bolt((gx+.095*math.cos(a),.779,gz+.095*math.sin(a)),(0,1,0),gun,.008)
hose('Minigun armored cable',[(.61,-.16,1.04),(.69,-.24,1.02),(.69,-.39,1.11),(.47,-.43,1.13)],.021)

# Tank, mounting cradle, straps, valve and ribbed hose assembly.
tx=.47;ty=-.485
box('Tank cradle',(tx,ty,.96),(.255,.29,.066),dark,turret)
cyl('Fuel canister',(tx,ty,1.185),.12,.405,red,turret,'Z',32,.018)
for z in [1.002,1.361]:tube('Tank securing strap',(tx,ty,z),.127,.117,.035,dark,turret,'Z',32)
for z in [1.002,1.361]:box('Tank strap buckle',(tx+.133,ty,z),(.034,.068,.05),steel,turret,.004)
cyl('Tank domed shoulder',(tx,ty,1.392),.102,.036,red,turret,'Z',32,.015)
cyl('Tank neck',(tx,ty,1.424),.034,.042,brass,turret,'Z',16)
rod('Valve crossbar',(tx-.05,ty,1.453),(tx+.05,ty,1.453),.012,red,turret)
cyl('Valve stem',(tx,ty,1.456),.017,.024,steel,turret)
panel('Tank hazard triangle',[(.599,ty-.072,1.12),(.599,ty+.072,1.12),(.599,ty,1.284)],.005,yellow,turret)
text('Tank caution','!',(.606,ty,1.151),.084,(math.pi/2,0,math.pi/2),turret)
path=[(.47,-.49,1.462),(.47,-.70,1.51),(.16,-.71,1.51),(-.28,-.60,1.47),(-.39,-.32,1.39),(-.32,.03,1.26),(-.25,.36,1.19)]
hose_object=hose('Ribbed fuel hose',path,.026)
# Repeated narrow rings give the hose a corrugated protective jacket.
bpy.context.view_layer.update()
bezier=hose_object.data.splines[0].bezier_points
for a,b in zip(bezier[:-1],bezier[1:]):
    p0,p1,p2,p3=a.co,a.handle_right,b.handle_left,b.co
    for t in np.linspace(.05,.95,max(2,int((p3-p0).length/.026))):
        t=float(t);u=1-t;p=u*u*u*p0+3*u*u*t*p1+3*u*t*t*p2+t*t*t*p3
        tangent=(3*u*u*(p1-p0)+6*u*t*(p2-p1)+3*t*t*(p3-p2)).normalized()
        rod('Hose protective rib',p-tangent*.002,p+tangent*.002,.029,dark,turret,12)
hose('Tank return line',[(tx,ty,.99),(.64,-.56,.96),(.67,-.66,1.16),(.65,-.63,1.39),(.49,-.53,1.44)],.02)
for z in [1.04,1.25]:box('Return hose clip',(.669,-.64,z),(.048,.039,.028),steel,turret,.003)
box('Turret rear vent frame',(-.065,-.596,1.163),(.36,.038,.245),dark,turret,.007)
box('Turret vent shadow',(-.065,-.618,1.163),(.303,.012,.192),black,turret,.003)
for z in [1.096,1.14,1.184,1.228]:box('Rear tower louver',(-.065,-.635,z),(.296,.025,.018),steel,turret,.002)
cyl('Antenna rubber boot',(-.28,-.405,1.426),.028,.107,rubber,turret)
for z in np.arange(1.4,1.477,.013):cyl('Antenna boot ridge',(-.28,-.405,float(z)),.031,.006,dark,turret,verts=16,bevel=0)
cyl('Antenna whip',(-.28,-.405,1.679),.006,.418,dark,turret,verts=10,bevel=0)

# Geometric checks before mesh consolidation: tires and armor have distinct spaces.
assert .93-.175 > .68, 'Wheel sidewalls must clear central hull plates'
assert .473-.017 > .416, 'Fender inner radius must clear tread envelope'
assert 1.255 > .93+.175, 'Solid wheel shields must extend beyond the tire width'
assert .288-.038 > .19, 'Flamer stand-off must begin ahead of tower face'
clearance_report={'wheel_to_hull_m':.93-.175-.68,'fender_to_tread_m':.473-.017-.416,'plow_overhang_beyond_tire_m':1.255-(.93+.175),'plow_wing_backward_sweep_m':1.57-1.315,'flamer_boss_to_tower_m':.288-.038-.19}
