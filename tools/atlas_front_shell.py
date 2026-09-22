"""Compact folded glacis and shoulder armor, in Godot metres."""
from mathutils import Vector


def add_front_shell(*, plate, box, bolt, tube, ring,
                    paint, secondary, steel, edge_steel, dark, lamp):
    normal = Vector((0, .437, -.38)).normalized()
    center = Vector((0, .23, -.9465))

    def front_panel(name, x0, x1, material=paint, depth=.040, offset=0):
        outline = [(x0, .040, -1.165), (x1, .040, -1.165),
                   (x1, .420, -.728), (x0, .420, -.728)]
        return plate(name, [tuple(Vector(p) + normal * offset) for p in outline],
                     normal, depth, material, b=.005)

    # A single structural closure supports the three flush armor sections.
    # Its face is 4 mm below the panel backs; seams reveal only that small depth.
    front_panel('Glacis structural closure', -.695, .695, secondary, .042, -.045)
    for x0, x1, title in [(-.687, -.429, 'left cheek'),
                          (-.423, .423, 'center'), (.429, .687, 'right cheek')]:
        front_panel('Folded front armor ' + title, x0, x1)
        for x in (x0 + .030, x1 - .030):
            for y, z in ((.384, -.77), (.084, -1.114)):
                p = Vector((x, y, z))
                p -= normal * (p - center).dot(normal)
                bolt(p + normal * .021, normal, r=.0105)

    # The forehead bridges the deck and front plane without a black void.
    plate('Front forehead structural fold',
          [(-.696, .407, -.736), (.696, .407, -.736),
           (.696, .472, -.659), (-.696, .472, -.659)],
          (0, .76, -.65), .032, secondary, b=.003)
    plate('Front forehead armor fold',
          [(-.687, .431, -.733), (.687, .431, -.733),
           (.687, .4788, -.665), (-.687, .4788, -.665)],
          (0, .69, -.73), .021, paint, b=.004)

    # The lower front folds back toward the keel. An actual four-sided opening
    # surrounds the primary receiver, rather than a receiver pasted on a slab.
    def apron_z(y):
        return -1.168 + (.040-y) * (.044/.325)

    def apron(name, x0, x1, y0, y1, material=paint, depth=.037, offset=0):
        return plate(name, [(x0,y0,apron_z(y0)+offset),
                            (x1,y0,apron_z(y0)+offset),
                            (x1,y1,apron_z(y1)+offset),
                            (x0,y1,apron_z(y1)+offset)],
                     (0,-.044,-.325), depth, material, b=.004)

    for side in (-1, 1):
        lo, hi = sorted((side*.242, side*.687))
        apron('Joined lower front cheek',lo,hi,-.285,.035)
        # Recessed headlamp tray is welded into the folded cheek. The thick
        # surrounding rim protects the lens and ends at the cheek's outer edge.
        x=side*.548
        box('Headlamp structural pocket',(x,.018,-1.177),(.230,.159,.067),secondary,b=.007)
        box('Headlamp recessed well',(x,.020,-1.214),(.183,.112,.008),dark,b=.003)
        for xx in (x-.107,x+.107):
            box('Headlamp armored upright',(xx,.020,-1.219),(.017,.143,.023),secondary,b=.003)
        for yy in (-.043,.083):
            box('Headlamp armored sill',(x,yy,-1.219),(.212,.017,.023),secondary,b=.003)
        box('Headlamp steel inner rim',(x,.020,-1.218),(.155,.087,.008),steel,b=.005)
        box('Headlamp ivory lens',(x,.020,-1.224),(.133,.065,.006),lamp,b=.004)
        for y in (-.248,-.103):
            bolt((side*.650,y,apron_z(y)-.019),(0,0,-1),r=.0105)
        # Seated recovery eye: mounting block and pivot have real contact.
        box('Recovery eye mounting clevis',(side*.514,-.208,-1.157),(.074,.104,.061),secondary,b=.008)
        ring('Forged recovery eye',(side*.514,-.229,-1.192),(0,0,1),.046,.030,.016,steel)

    apron('Receiver upper bridge',-.236,.236,-.026,.035)
    apron('Receiver lower impact apron',-.236,.236,-.285,-.174,secondary)
    box('Continuous lower front bumper',(0,-.302,-1.118),(1.38,.071,.086),secondary,b=.009)
    box('Front tool receiver',(0,-.10,-1.155),(.47,.14,.11),secondary,b=.010)
    box('Front receiver slot',(0,-.10,-1.213),(.31,.06,.012),dark,b=.004)
    for x in (-.198,.198):bolt((x,-.10,-1.212),(0,0,-1),r=.012)

    # Flush painted markings follow the actual glacis plane.
    for cx in (-.25,0,.25):
        outline=[]
        for x,t in [(-.062,0),(.02,0),(.11,.50),(.02,1),(-.062,1),(.025,.50)]:
            y=.14+t*.19
            outline.append(tuple(Vector((cx-x,y,-1.165+(y-.04)*(.437/.38)))+normal*.0217))
        plate('Inset directional chevron',outline,normal,.0025,secondary,b=0)


def add_shoulders(side, group, *, mesh, plate, box, bolt, cylinder, ring,
                  paint, secondary, steel, dark):
    # One folded cross-section joins the central hull roof to the side skirt.
    # The broad top is centered on X=.93, exactly under the published sockets.
    profile=[(.688,.437),(.688,.481),(.739,.500),(1.121,.500),
             (1.207,.414),(1.170,.395),(1.095,.460),(.739,.460)]

    def strip(name,z0,z1,off0=0,off1=0,material=paint,backing=False):
        outline=profile
        if backing:
            outline=[(x-.002,y-.006) for x,y in profile]
        n=len(outline)
        verts=[(side*x,y+off,z) for z,off in ((z0,off0),(z1,off1)) for x,y in outline]
        faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
        faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        return mesh(name,verts,faces,material,group,.003 if backing else .004)

    strip('Continuous shoulder structural channel',-.887,.887,material=secondary,backing=True)
    strip('Joined central shoulder armor',-.489,.489)
    for end in (-1,1):
        a,b=sorted((end*.495,end*.885))
        strip('Corner socket shoulder armor',a,b)
        a,b=sorted((end*.891,end*1.002))
        strip('Folded terminal track hood',a,b,
              -.065 if end<0 else 0,0 if end<0 else -.065)
        strip('Terminal hood structural seat',a,b,
              -.065 if end<0 else 0,0 if end<0 else -.065,secondary,True)
        z=end*.69;x=side*.93
        for dx in (-.145,.145):
            for dz in (-.151,.151):bolt((x+dx,.501,z+dz),group=group,r=.010)
        cylinder('Docking point armor seat',(x,.493,z),(x,.508,z),.102,dark,group,32,.002)
        cylinder('Armor-seated corner socket',(x,.506,z),(x,.538,z),.088,secondary,group,32,.004)
        ring('Corner socket machined lip',(x,.541,z),(0,1,0),.074,.055,.008,steel,group,32)

    # A thin service plate sits in the shoulder, with a narrow seam rather than
    # an extra black armor layer. Its fasteners are rooted on the metal face.
    box('Shoulder service seal',(side*.93,.5005,0),(.278,.003,.770),dark,group,b=.003)
    box('Flush shoulder access plate',(side*.93,.504,0),(.269,.004,.760),secondary,group,b=.002)
    for dx in (-.111,.111):
        for z in (-.348,.348):bolt((side*.93+dx,.507,z),group=group,r=.008)
    for z in (-.23,0,.23):
        box('Inset shoulder service groove',(side*.93,.5063,z),(.184,.001,.010),dark,group,b=.001)

    # Inboard folded walls connect the hood to the hull below. They remain
    # inside X=.70; the nearest moving track hinge begins outside X=.711.
    for end in (-1,1):
        plate('Shoulder inner closure',
              [(side*.687,.160,end*1.002),(side*.687,.264,end*.891),
               (side*.687,.477,end*.670),(side*.687,.481,end*.670),
               (side*.687,.481,end*.891),(side*.687,.417,end*1.002)],
              (side,0,0),.020,paint,group,.003)
