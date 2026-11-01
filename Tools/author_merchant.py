"""Author Matěj in Blender. Run Blender --background --python this_file -- [--preview].
All shapes, materials and lighting are original, editable geometry. Front is -Y.

Matěj follows the town's art direction (the low-poly and isometric rules
from the blender-skills pack): flat shading, no subdivision, at most a single
bevel segment, low segment counts, no stitching or other micro detail, plain
colours instead of noise textures, and the town's own warm sun with a cool
ambient fill under an orthographic camera.
"""
import bpy
import math
import sys
import json
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'Art' / 'Merchant'
ASSET = ROOT / 'Pilire' / 'Assets.xcassets' / 'MerchantMatej.imageset'
PREVIEW = '--preview' in sys.argv
ART.mkdir(parents=True, exist_ok=True)
ASSET.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for data in list(bpy.data.materials):
    bpy.data.materials.remove(data)

PARENT = None
MODELS = []
# Low-poly budget: every primitive is capped to the facet counts the town uses.
SPHERE_SEGMENTS, SPHERE_RINGS = 12, 8
LOFT_SEGMENTS, TUBE_SIDES, CYLINDER_SIDES = 14, 8, 10
# Stitching, seams and ruled lines vanish at 170 points and break the town's
# flat-colour look, so these details are not modelled.
MICRO_DETAIL = ('seam', 'stitch', 'strand', 'Faint ledger line', 'Visible page edge',
                'fringe', 'spiral', 'piping', 'Ear inner fold', 'vein', 'crease',
                'Iron nail head', 'Scarf fold', 'Sack tie loop', 'Wheel inner edge')


def is_micro(name):
    return any(k in name for k in MICRO_DETAIL)

def material(name, color, roughness=.7, metallic=0):
    h = color.lstrip('#')
    rgb = [int(h[i:i+2], 16) / 255 for i in (0,2,4)]
    linear = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*linear, 1)
    bs.inputs['Roughness'].default_value = roughness
    bs.inputs['Metallic'].default_value = metallic
    m.diffuse_color = (*linear, 1)
    return m

coat = material('Sage wool', '#667C59', .89)
coat_dark = material('Folded wool', '#4B6045', .88)
coat_light = material('Wool piping', '#8A9971', .88)
linen = material('Unbleached linen', '#E9DDB8', .88)
linen_dark = material('Linen folds', '#C4B58C', .92)
rust = material('Terracotta scarf', '#B87551', .87)
rust_light = material('Scarf woven edge', '#D69466', .88)
leather = material('Chestnut leather', '#765035', .58)
leather_dark = material('Leather edges', '#50382B', .66)
leather_light = material('Leather stitching', '#B18C5D', .8)
skin = material('Warm skin', '#DCA877', .65)
skin_rosy = material('Cheeks and nose', '#D39A70', .72)
hair = material('Warm silver beard', '#DDD5BA', .84)
hair_shadow = material('Beard sculpted strands', '#BCB496', .9)
hair_light = material('Beard tips', '#EAE3CC', .84)
eye = material('Deep brown eyes', '#352E22', .24)
glint = material('Eye catchlight', '#FFFAE9', .18)
smile = material('Smile shadow', '#9A6248', .9)
brass = material('Aged warm brass', '#BE9650', .38, .55)
wood = material('Honey oak', '#916A42', .82)
wood_light = material('Fresh plank edges', '#B68F5B', .8)
wood_dark = material('End grain', '#795A3B', .88)
iron = material('Soft charcoal iron', '#494E43', .5, .32)
book_cover = material('Oxblood ledger', '#8D4F38', .62)
ink = material('Ledger ink', '#8F8164', .9)


def finish(o, name, m, smooth=False):
    o.name = name
    if m: o.data.materials.append(m)
    if o.type == 'MESH':
        # Flat facets, like every building and tree in the town.
        for p in o.data.polygons: p.use_smooth = smooth
    if PARENT: o.parent = PARENT
    MODELS.append(o)
    return o


def empty(name):
    o = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(o)
    return o


def sphere(name, p, scale, m, segments=SPHERE_SEGMENTS):
    if is_micro(name): return None
    bpy.ops.mesh.primitive_uv_sphere_add(segments=min(segments,SPHERE_SEGMENTS),
                                         ring_count=SPHERE_RINGS, location=p)
    o = bpy.context.object
    o.scale = scale
    return finish(o,name,m)


def bevel_once(o, width):
    # A single chamfer catches the sun on edges without rounding them off.
    b = o.modifiers.new('Single chamfer','BEVEL')
    b.width = width; b.segments = 1; b.limit_method = 'ANGLE'


def box(name,p,size,m,bevel=.025,rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=p)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rotation: o.rotation_euler = rotation
    if bevel: bevel_once(o, min(bevel*.6, min(size)*.3))
    return finish(o,name,m)


def cylinder(name,a,b,r,m,vertices=CYLINDER_SIDES):
    a,b = Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=min(vertices,CYLINDER_SIDES), radius=r,
                                        depth=(b-a).length, location=(a+b)/2)
    o=bpy.context.object
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return finish(o,name,m)


def mesh(name, vertices, faces, m, bevel=0, subdivision=0):
    # `subdivision` is accepted for older call sites but ignored: no smoothing.
    data=bpy.data.meshes.new(name)
    data.from_pydata(vertices,[],faces); data.update()
    o=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(o)
    if bevel: bevel_once(o, bevel*.6)
    return finish(o,name,m)


def loft(name, rings, m, segments=LOFT_SEGMENTS, subdivision=0):
    # Each ring is z, x radius, y radius, x centre, y centre.
    segments=min(segments,LOFT_SEGMENTS)
    verts=[]
    for z,rx,ry,cx,cy in rings:
        for i in range(segments):
            t=2*math.pi*i/segments
            verts.append((cx+rx*math.cos(t),cy+ry*math.sin(t),z))
    faces=[]
    for j in range(len(rings)-1):
        for i in range(segments):
            a=j*segments+i; b=j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces += [tuple(range(segments-1,-1,-1)), tuple((len(rings)-1)*segments+i for i in range(segments))]
    return mesh(name,verts,faces,m,subdivision=subdivision)


def curve(name, points, radius, m, cyclic=False):
    if is_micro(name): return None
    data=bpy.data.curves.new(name,'CURVE'); data.dimensions='3D'
    data.resolution_u=4; data.bevel_depth=radius; data.bevel_resolution=1
    spline=data.splines.new('BEZIER'); spline.bezier_points.add(len(points)-1)
    for b,p in zip(spline.bezier_points,points):
        b.co=p; b.handle_left_type='AUTO'; b.handle_right_type='AUTO'
    spline.use_cyclic_u=cyclic
    o=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(o)
    return finish(o,name,m)


def tube(name, points, radii, m, sides=TUBE_SIDES):
    # Catmull-Rom centreline with interpolated radii; coherent local rings.
    sides=min(sides,TUBE_SIDES)
    pp=[Vector(p) for p in points]
    samples=[]; rr=[]
    for i in range(len(pp)-1):
        a=pp[max(0,i-1)]; b=pp[i]; c=pp[i+1]; d=pp[min(len(pp)-1,i+2)]
        for j in range(3):
            t=j/3
            samples.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
            rr.append(radii[i]*(1-t)+radii[i+1]*t)
    samples.append(pp[-1]); rr.append(radii[-1])
    verts=[]
    for i,(p,r) in enumerate(zip(samples,rr)):
        tangent=(samples[min(i+1,len(samples)-1)]-samples[max(0,i-1)]).normalized()
        q=tangent.to_track_quat('Z','Y')
        for k in range(sides):
            t=math.tau*k/sides
            verts.append(tuple(p+q@Vector((r*math.cos(t),r*math.sin(t),0))))
    faces=[]
    for j in range(len(samples)-1):
        for k in range(sides):
            a=j*sides+k; b=j*sides+(k+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces += [tuple(range(sides-1,-1,-1)),tuple((len(samples)-1)*sides+k for k in range(sides))]
    return mesh(name,verts,faces,m)


def panel(name,points,m,thickness=.016,bevel=.012):
    n=len(points)
    verts=list(points)+[(x,y+thickness,z) for x,y,z in points]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,verts,faces,m,bevel=bevel)


def torus(name,p,major,minor,m,rotation=None):
    bpy.ops.mesh.primitive_torus_add(major_segments=20,minor_segments=6,location=p,major_radius=major,minor_radius=minor)
    o=bpy.context.object
    if rotation: o.rotation_euler=rotation
    return finish(o,name,m)

character=empty('MATEJ — character')
PARENT=character
# Sturdy shoes have a distinct sole, toe and ankle cuff.
for side in [-1,1]:
    x=side*.145
    box('Layered boot sole',(x,-.065,.060),(.255,.405,.075),leather_dark,.035)
    sphere('Rounded leather toe',(x,-.089,.138),(.137,.226,.115),leather)
    loft('Boot ankle',[(.13,.111,.119,x,.015),(.20,.112,.112,x,.025),(.32,.105,.10,x,.033),(.34,.111,.103,x,.033)],leather)
    loft('Rolled boot cuff',[(.30,.116,.112,x,.033),(.335,.116,.112,x,.033),(.36,.108,.106,x,.033)],leather_dark)
    loft('Trousers',[(.31,.085,.081,x,.036),(.42,.098,.098,x,.03),(.60,.113,.107,x,0),(.82,.12,.116,x,0)],coat_dark)
    curve('Boot welt seam',[(x+.118*math.cos(t),-.065+.19*math.sin(t),.102) for t in [i*math.tau/24 for i in range(24)]],.0035,leather_light,True)

loft('Tailored coat body',[
    (.48,.32,.208,0,.018),(.52,.348,.226,0,.013),(.72,.325,.222,0,0),
    (.98,.282,.207,0,0),(1.17,.293,.205,0,0),(1.39,.342,.211,0,0),
    (1.49,.345,.197,0,.012),(1.57,.232,.132,0,.015),(1.60,.16,.102,0,.012)
],coat)
# Front linen insert and broad sculpted lapels make the coat readable at 140pt.
panel('Linen shirt front',[(-.105,-.204,1.55),(.105,-.204,1.55),(.115,-.226,1.18),(-.115,-.226,1.18)],linen)
for side in [-1,1]:
    panel('Folded coat lapel',[(side*.10,-.212,1.565),(side*.23,-.209,1.49),(side*.155,-.250,1.35),(side*.055,-.246,1.20)],coat_dark,.022,.018)
    curve('Lapel raised seam',[(side*.10,-.222,1.56),(side*.22,-.225,1.49),(side*.145,-.266,1.35),(side*.06,-.260,1.22)],.004,coat_light)
    curve('Tailored front seam',[(side*.055,-.210,1.14),(side*.061,-.222,.93),(side*.085,-.233,.70),(side*.10,-.224,.52)],.005,coat_dark)
    curve('Hem piping',[(side*.10,-.225,.52),(side*.22,-.185,.515),(side*.31,-.11,.515)],.0045,coat_light)
for z in [1.28,1.13,.92,.79]:
    sphere('Brass coat button',(.071,-.231,z),(.014,.010,.014),brass,20)
# Belt wraps the torso; buckle includes the recessed leather centre.
loft('Leather waist belt',[(.995,.287,.215,0,0),(1.054,.287,.215,0,0)],leather,subdivision=0)
box('Belt buckle',(.011,-.223,1.026),(.078,.020,.069),brass,.012)
box('Buckle leather centre',(.011,-.237,1.026),(.049,.007,.040),leather_dark,.006)
cylinder('Buckle tongue',(.006,-.243,1.01),(.006,-.243,1.043),.004,brass)

# Sleeves follow the elbow instead of intersecting cylindrical primitives.
tube('Left tailored sleeve',[(-.30,.015,1.46),(-.405,-.017,1.34),(-.47,-.14,1.17),(-.385,-.345,1.175)], [.122,.124,.105,.078],coat)
tube('Right tailored sleeve',[(.30,.015,1.46),(.41,-.025,1.35),(.47,-.075,1.22),(.603,-.15,1.225)], [.122,.124,.103,.074],coat)
for name,a,b,r in [
    ('Left linen cuff',(-.40,-.319,1.175),(-.370,-.378,1.175),.080),
    ('Right linen cuff',(.575,-.135,1.225),(.631,-.163,1.225),.077)]:
    cylinder(name,a,b,r,linen)
    d=(Vector(b)-Vector(a)).normalized()
    cylinder(name+' wool seam',Vector(a)-d*.009,Vector(a)+d*.007,r*1.04,coat_dark)
# The left hand supports an open ledger. Individual bent fingers are visible.
sphere('Left hand palm',(-.355,-.437,1.155),(.080,.087,.047),skin)
for i,x in enumerate([-.419,-.384,-.35,-.317]):
    tube('Left curled finger',[(x,-.464,1.137),(x,-.507,1.15),(x,-.524,1.185)], [.017,.019,.014],skin,12)
tube('Left thumb',[(-.285,-.424,1.155),(-.267,-.47,1.19),(-.282,-.490,1.208)],[.024,.026,.018],skin,14)
# Hand on the cart handle: thumb and fingers wrap around the wood.
sphere('Right hand palm',(.657,-.178,1.225),(.069,.060,.069),skin)
for i,z in enumerate([1.186,1.215,1.244,1.272]):
    tube('Right gripping finger',[(.660,-.185,z),(.686,-.231,z),(.657,-.249,z)],[.016,.019,.014],skin,12)
tube('Right thumb',[(.620,-.177,1.267),(.628,-.226,1.28),(.652,-.237,1.26)],[.025,.024,.018],skin,14)

# Open book, a raised spine, cream pages and discreet ruled lines.
book=empty('Open ledger'); book.parent=character
book.location=(-.36,-.461,1.198)
old_parent=PARENT; PARENT=book
for side in [-1,1]:
    cover=box('Ledger leather cover',(side*.093,0,-.021),(.191,.245,.018),book_cover,.012,rotation=(0,side*.10,0))
    pages=box('Layered paper block',(side*.090,0,0),(.177,.228,.027),linen,.005,rotation=(0,side*.10,0))
    for i in range(3):
        curve('Visible page edge',[(side*.015,-.116,-.008+i*.006),(side*.17,-.116,-.008+i*.006)],.0012,linen_dark)
    for j in range(4):
        curve('Faint ledger line',[(side*.028,-.074+j*.037,.023),(side*.146,-.074+j*.037,.023-side*.010)],.0012,ink)
cylinder('Ledger raised spine',(0,-.12,.014),(0,.12,.014),.008,leather_dark)
box('Bookmark',(.034,-.13,.023),(.018,.050,.004),rust,.002)
PARENT=old_parent

# Satchel flap, thickness and a cross-body leather strap.
box('Leather satchel',(.312,-.10,.865),(.242,.166,.282),leather,.045)
box('Satchel flap',(.312,-.193,.935),(.246,.028,.142),leather_dark,.032)
box('Satchel buckle',(.312,-.216,.873),(.055,.012,.065),brass,.012)
box('Buckle recess',(.312,-.224,.875),(.031,.005,.039),leather,.006)
curve('Satchel flap stitching',[(.216,-.213,.982),(.213,-.219,.903),(.31,-.220,.884),(.408,-.214,.903),(.408,-.211,.982)],.0026,leather_light)
strap_points=[(-.18,-.144,1.57),(-.095,-.237,1.40),(.042,-.252,1.20),(.19,-.236,1.01),(.299,-.20,.98)]
# A flat ribbon rather than a round cord.
vertices=[]
for x,y,z in strap_points:
    vertices += [(x-.029,y-.014,z+.018),(x+.029,y-.014,z-.018)]
strap=mesh('Flat satchel shoulder strap',vertices,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(len(strap_points)-1)],leather)
s=strap.modifiers.new('Leather thickness','SOLIDIFY'); s.thickness=.015
curve('Strap edge stitch',[(x-.020,y-.023,z+.012) for x,y,z in strap_points],.0018,leather_light)

# Head is a sculpted pear-shaped mesh. Add all features to a shared head pivot.
head_start=len(MODELS)
loft('Sculpted friendly head',[
    (1.71,.095,.090,0,-.020),(1.76,.153,.139,0,-.020),(1.84,.216,.181,0,-.012),
    (1.96,.247,.195,0,0),(2.055,.239,.191,0,.008),(2.14,.204,.158,0,.015),(2.185,.12,.10,0,.017)
],skin,segments=48,subdivision=2)
sphere('Neck',(0,.012,1.66),(.105,.096,.137),skin)
for side in [-1,1]:
    sphere('Soft cheek',(side*.146,-.159,1.943),(.073,.052,.064),skin_rosy)
    sphere('Ear',(side*.238,.008,1.978),(.052,.046,.078),skin)
    sphere('Ear inset',(side*.268,-.019,1.976),(.018,.018,.045),skin_rosy)
    # Two open, identical dot eyes sitting proud of the face. No lids or dark
    # rims: at portrait size those read as a squint, and the far eye vanished.
    sphere('Kind dot eye',(side*.090,-.200,2.040),(.025,.016,.031),eye)
    sphere('Eye catchlight',(side*.090+.008,-.214,2.052),(.007,.004,.007),glint)
    curve('Friendly arched eyebrow',[(side*.048,-.196,2.104),(side*.090,-.212,2.118),(side*.136,-.194,2.104)],.013,hair_shadow)
    sphere('Silver sideburn',(side*.209,-.065,1.992),(.029,.061,.093),hair)
# A continuous tapering beard, with swept sculpted locks rather than cheek balls.
loft('Full silver beard',[
    (1.665,.045,.036,0,-.101),(1.695,.097,.064,0,-.103),(1.75,.156,.094,0,-.100),
    (1.81,.195,.126,0,-.083),(1.875,.211,.155,0,-.065),(1.917,.186,.142,0,-.055)
],hair,segments=48,subdivision=2)
for side in [-1,1]:
    tube('Swept moustache',[(side*.009,-.239,1.949),(side*.070,-.254,1.930),(side*.135,-.227,1.932),(side*.188,-.184,1.960)], [.023,.038,.027,.006],hair_light)
    curve('Moustache sculpted strand',[(side*.025,-.264,1.953),(side*.092,-.269,1.945),(side*.155,-.229,1.949)],.0027,hair_shadow)
sphere('Pear nose bridge',(0,-.185,2.006),(.046,.050,.068),skin)
sphere('Warm rounded nose',(0,-.234,1.991),(.058,.058,.047),skin_rosy)
curve('Small smile',[(-.059,-.205,1.885),(0,-.225,1.877),(.063,-.203,1.893)],.007,smile)
sphere('Lower lip',(0,-.223,1.874),(.032,.012,.012),skin_rosy)
# Hair peeking out below the brim.
for side in [-1,1]:
    tube('Temple curl',[(side*.177,.025,2.135),(side*.218,-.02,2.107),(side*.220,-.062,2.065)],[.044,.033,.015],hair)

# A cloth hat with a shaped, turned-up brim and leather band.
verts=[]; n=20
for radius in [.65,1]:
    for i in range(n):
        a=math.tau*i/n
        z=2.155+(.018*math.sin(a+.4)+.027*math.cos(a*2+.5))*(radius**3)
        verts.append((.354*radius*math.cos(a),.297*radius*math.sin(a),z))
brim=mesh('Soft curved hat brim',verts,[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],coat_dark)
s=brim.modifiers.new('Felt thickness','SOLIDIFY'); s.thickness=.028
bevel_once(brim,.008)
loft('Soft asymmetrical hat crown',[
    (2.15,.240,.211,0,.007),(2.19,.245,.217,-.004,.011),(2.28,.221,.192,-.015,.020),
    (2.37,.166,.145,-.035,.020),(2.405,.073,.068,-.047,.017),(2.41,.015,.015,-.05,.015)
],coat,segments=48,subdivision=2)
loft('Hat leather band',[(2.171,.247,.218,-.003,.010),(2.216,.240,.211,-.006,.013)],leather,segments=64,subdivision=0)
curve('Hat crown seam',[(.217*math.cos(t)-.015,.193*math.sin(t)+.020,2.285) for t in [i*math.tau/48 for i in range(48)]],.0027,coat_light,True)
# Small brass leaf pin, a quiet echo of the game's leaf resource.
leaf=panel('Brass leaf pin',[(.111,-.211,2.198),(.138,-.217,2.233),(.137,-.213,2.271),(.105,-.216,2.249),(.095,-.211,2.216)],brass,.007,.004)
curve('Leaf pin vein',[(.109,-.222,2.208),(.131,-.224,2.256)],.002,wood_light)
# Group the head around its neck and turn it a little toward the viewer.
head=empty('Head — gentle turn'); head.parent=character; head.location=(0,0,1.95)
bpy.context.view_layer.update()
for o in MODELS[head_start:]:
    world=o.matrix_world.copy(); o.parent=head; o.matrix_world=world
# Turned toward the camera so both eyes stay clear of the nose and cheeks.
head.rotation_euler[2]=.32

# Scarf has volume at the neck and a hanging end with an uneven fold.
PARENT=character
loft('Wrapped scarf collar',[(1.591,.128,.112,0,-.015),(1.625,.149,.131,0,-.018),(1.682,.138,.120,0,-.018)],rust,segments=40,subdivision=1)
panel('Scarf hanging tail',[(-.124,-.178,1.65),(-.032,-.202,1.64),(-.015,-.257,1.37),(-.105,-.263,1.347),(-.135,-.240,1.48)],rust,.030,.014)
curve('Scarf fold',[(-.092,-.203,1.63),(-.069,-.248,1.49),(-.070,-.278,1.369)],.007,rust_light)
for x in [-.097,-.079,-.061,-.043,-.025]:
    curve('Scarf fringe',[(x,-.270,1.37),(x+.003,-.273,1.337)],.003,linen_dark)
character.location.x=-.43

# Handcart: real open spokes, rims, joinery and a few useful travel supplies.
PARENT=None
cart=empty('HANDCART — oak and iron'); cart.location=(.45,.10,0); cart.scale=(.86,.86,.86); PARENT=cart
box('Cart underframe',(0,0,.433),(.82,.64,.085),wood_dark,.026)
for i in range(6):
    box('Cart floor plank',(-.34+i*.136,0,.49),(.129,.60,.038),wood_light if i%2 else wood,.009)
for side in [-1,1]:
    for y in [-.29,.29]:
        box('Upright cart corner',(side*.386,y,.643),(.047,.047,.376),wood,.009)
        for z in [.55,.667,.785]:
            sphere('Iron nail head',(side*.414,y,z),(.008,.009,.009),iron,16)
    for z in [.55,.667,.785]:
        box('Side rail',(side*.390,0,z),(.035,.66,.085),wood_light if z==.785 else wood,.009)
    for z in [.55,.667]:
        box('End gate rail',(0,side*.307,z),(.77,.033,.085),wood_light,.008)
    # Wheel axis is X, and spokes are fully open to the background.
    x=side*.485
    torus('Iron tyre',(x,.05,.276),.247,.021,iron,rotation=(0,math.pi/2,0))
    torus('Oak wheel rim',(x,.05,.276),.215,.030,wood_dark,rotation=(0,math.pi/2,0))
    torus('Wheel inner edge',(x+side*.014,.05,.276),.222,.012,wood_light,rotation=(0,math.pi/2,0))
    for i in range(8):
        a=math.tau*i/8
        cylinder('Carved oak spoke',(x,.05,.276),(x,.05+.207*math.cos(a),.276+.207*math.sin(a)),.015,wood_light,16)
    cylinder('Wheel hub',(x-side*.046,.05,.276),(x+side*.044,.05,.276),.053,wood_dark)
    cylinder('Brass axle cap',(x+side*.044,.05,.276),(x+side*.052,.05,.276),.027,brass)
cylinder('Iron axle',(-.51,.05,.276),(.51,.05,.276),.023,iron)
# Two shaped shafts, one of which lies under Matěj's gripping hand.
curve('Left handle shaft',[(-.34,-.12,.44),(-.34,-.25,.79),(-.265,-.337,1.395)],.023,wood_dark)
curve('Second handle shaft',[(.32,-.12,.44),(.12,-.28,.88),(-.12,-.337,1.395)],.023,wood_dark)
cylinder('Rounded handle grip',(-.287,-.337,1.395),(-.099,-.337,1.395),.028,wood_light)
# Linen sack with pinched neck and a tied string.
loft('Sack of supplies',[(.51,.11,.105,-.15,.045),(.57,.145,.14,-.15,.045),(.78,.16,.135,-.16,.057),(.91,.11,.09,-.16,.06),(.948,.040,.034,-.16,.06),(.99,.075,.057,-.16,.06)],linen,segments=32,subdivision=2)
torus('Sack neck cord',(-.16,.06,.945),.039,.006,leather_light)
curve('Sack tie loop',[(-.17,.023,.947),(-.22,-.014,.956),(-.235,.018,.97),(-.183,.031,.948)],.004,leather_light)
curve('Sack stitched crease',[(-.22,-.055,.57),(-.23,-.066,.71),(-.20,-.031,.87)],.003,linen_dark)
# A rolled blanket: contrast in shape, with a visible spiral on its end.
cylinder('Rolled wool blanket',(-.08,-.14,.902),(.36,-.14,.902),.128,rust)
for x in [.04,.24]:
    torus('Blanket linen tie',(x,-.14,.902),.130,.010,linen_dark,rotation=(0,math.pi/2,0))
spiral=[]
for i in range(110):
    t=i/109*math.pi*4.5; r=.009+.105*i/109
    spiral.append((.369,-.14+r*math.cos(t),.902+r*math.sin(t)))
curve('Rolled blanket spiral',spiral,.0045,rust_light)
# Two parcels and a wax seal among the supplies.
box('Parcel at back',(.17,.17,.664),(.29,.25,.28),linen,.035)
for x in [.14,.20]:
    box('Parcel string',(x,.17,.808),(.007,.257,.006),leather_light,.001)
box('Parcel cross string',(.17,.17,.811),(.297,.007,.006),leather_light,.001)
sphere('Wax parcel seal',(.17,.155,.819),(.024,.024,.007),rust)
for i in range(2):
    cylinder('Short oak stock',(-.23+i*.10,.18,.64),(-.23+i*.10,.18,.94),.042,wood)
PARENT=None

# A transparent roadside portrait matching the cream UI and town terrain.
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=24 if PREVIEW else 64
scene.cycles.use_denoising=True
scene.render.film_transparent=True
scene.render.image_settings.file_format='PNG'
scene.render.image_settings.color_mode='RGBA'
scene.render.image_settings.color_depth='8'
scene.render.resolution_percentage=100
# The town's light rig (BuildingDetailSheet): a warm directional sun at 950
# and a cool ambient at 600. The world plays the ambient, the sun is below.
scene.world.use_nodes=True
scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.85,.90,.96,1)
scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.45
# Standard keeps flat colours as saturated as SceneKit draws them.
scene.view_settings.view_transform='Standard'
scene.view_settings.look='None'
scene.view_settings.exposure=0
# Native Metal when available, CPU remains a deterministic fallback.
try:
    if '--cpu' in sys.argv or '--metal' not in sys.argv:
        raise RuntimeError('CPU render requested')
    prefs=bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type='METAL'; prefs.get_devices()
    devices=[d for d in prefs.devices if d.type=='METAL']
    if devices:
        for d in prefs.devices: d.use=d.type=='METAL'
        scene.cycles.device='GPU'
        print('MERCHANT_RENDER_DEVICE', [d.name for d in devices])
except Exception as e:
    print('MERCHANT_CPU_RENDER',str(e))


def sun(name,direction,strength,color,angle):
    data=bpy.data.lights.new(name,'SUN'); data.energy=strength; data.color=color
    data.angle=math.radians(angle)
    o=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(o)
    o.location=Vector(direction).normalized()*6
    o.rotation_euler=(-Vector(direction)).to_track_quat('-Z','Y').to_euler()
# High and from camera-left, as on the town's buildings, with crisp shadows.
sun('Town sun',(-.71,-.81,1.35),2.4,(1,.96,.88),4)
# A small roadside vignette anchors the approved character in the town.
# World-space opacity makes the meadow and road dissolve together into the UI.
portrait_models=tuple(MODELS)
character.location.z=-.0155  # boot soles meet the road; wheels already sit at z=.007
scenery=empty('ROADSIDE — softly fading meadow')
PARENT=scenery
# The meadow fades out along an ellipse around the pair; kept snug so the
# figure, not the grass, fills the portrait.
FADE_X,FADE_Y=2.15,1.20


def edge_fade(m):
    nodes=m.node_tree.nodes; links=m.node_tree.links
    geo=nodes.new('ShaderNodeNewGeometry')
    centre=nodes.new('ShaderNodeVectorMath'); centre.operation='SUBTRACT'
    centre.inputs[1].default_value=(.02,.08,0)
    links.new(geo.outputs['Position'],centre.inputs[0])
    ellipse=nodes.new('ShaderNodeVectorMath'); ellipse.operation='MULTIPLY'
    ellipse.inputs[1].default_value=(1/FADE_X,1/FADE_Y,0)
    links.new(centre.outputs['Vector'],ellipse.inputs[0])
    distance=nodes.new('ShaderNodeVectorMath'); distance.operation='LENGTH'
    links.new(ellipse.outputs['Vector'],distance.inputs[0])
    fade=nodes.new('ShaderNodeMapRange'); fade.clamp=True
    fade.interpolation_type='SMOOTHERSTEP'
    fade.inputs['From Min'].default_value=.405; fade.inputs['From Max'].default_value=.50
    links.new(distance.outputs['Value'],fade.inputs['Value'])
    transparent=nodes.new('ShaderNodeBsdfTransparent')
    mix=nodes.new('ShaderNodeMixShader')
    links.new(fade.outputs['Result'],mix.inputs[0])
    links.new(nodes.get('Principled BSDF').outputs[0],mix.inputs[1])
    links.new(transparent.outputs[0],mix.inputs[2])
    links.new(mix.outputs[0],nodes.get('Material Output').inputs['Surface'])
    return m


# Flat colours sampled from the town map itself: grass, path and its edge.
meadow=edge_fade(material('Meadow — town grass','#9ABE76',1))
road=edge_fade(material('Road — town path','#C0B088',1))
road_edge=edge_fade(material('Road — path edge','#A69771',1))
stone=edge_fade(material('Roadside grey stones','#A3A593',.94))
green=edge_fade(material('Bush foliage','#5F8C4D',.96))
green_light=edge_fade(material('Bush sunlit foliage','#78A35A',.96))
blade_mat=edge_fade(material('Bent meadow blades','#6E9A50',1))
flower_mat=edge_fade(material('Tiny meadow blossoms','#F1E6C4',.9))

bpy.ops.mesh.primitive_plane_add(size=2,location=(.02,.08,.003))
ground=finish(bpy.context.object,'Feathered grass clearing',meadow)
ground.scale=(1.35,.80,1)


def path_centre(x):
    return .04+.08*x+.03*math.sin(x*1.8)


def road_ribbon(name, extra, z, m):
    vertices=[]
    for i in range(15):
        x=-1.55+i*3.10/14
        y=path_centre(x)
        width=.335+.015*math.cos(x*3)+extra
        vertices += [(x,y-width,z),(x,y+width,z)]
    faces=[(i*2,i*2+2,i*2+3,i*2+1) for i in range(14)]
    return mesh(name,vertices,faces,m,subdivision=2)

road_ribbon('Organic path margin',.026,.005,road_edge)
road_ribbon('Path under boots and cart',0,.007,road)
# Small, softly faceted stones along the verge, clear of feet and wheels.
for i,(x,y,size) in enumerate([(-.78,-.35,.060),(-.69,-.38,.036),
                              (.47,-.31,.065),(.58,-.33,.038),(-.98,.12,.035)]):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=(x,y,size*.23+.003))
    o=bpy.context.object; o.scale=(size,size*.72,size*.32)
    o.rotation_euler[2]=i*1.34
    finish(o,'Rounded verge stone',stone,smooth=False)
# Low foliage suggests the edge of the town while keeping the face clear.
for centre,scale,m in [((-.87,.32,.110),(.19,.14,.12),green),
                       ((-.98,.28,.083),(.13,.12,.09),green_light),
                       ((-.76,.35,.079),(.13,.11,.085),green_light),
                       ((.84,.43,.105),(.20,.13,.11),green),
                       ((.96,.40,.074),(.13,.10,.08),green_light)]:
    sphere('Low roadside foliage',centre,scale,m,segments=16)


def grass_tuft(x,y,turn):
    for i in range(4):
        angle=turn+i*2.05
        height=.05+.012*(i%3)
        reach=.026+.008*(i%2)
        direction=Vector((math.cos(angle),math.sin(angle),0))
        side=Vector((-math.sin(angle),math.cos(angle),0))
        base=Vector((x,y,.006))
        verts=[]
        for j in range(4):
            t=j/3; width=.006*(1-t)+.0005
            point=base+direction*reach*t*t+Vector((0,0,height*t))
            verts += [tuple(point+side*width),tuple(point-side*width)]
        mesh('Curved meadow blade',verts,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(3)],blade_mat)
for x,y,turn in [(-.93,-.15,1.2),(-.57,-.43,.4),(.18,-.34,2.5),(.98,.04,.8)]:
    grass_tuft(x,y,turn)
for x,y,z in [(-.90,.25,.16),(-.82,.29,.14),(-.77,.33,.13)]:
    cylinder('Flower stem',(x,y,.01),(x,y,z),.003,blade_mat,12)
    for i in range(5):
        a=i*math.tau/5
        sphere('Tiny cream petal',(x+math.cos(a)*.012,y+math.sin(a)*.012,z),(.010,.010,.005),flower_mat,12)
PARENT=None
shadow_planes=[]
cam_data=bpy.data.cameras.new('Merchant portrait camera')
cam=bpy.data.objects.new('Merchant portrait camera',cam_data); bpy.context.collection.objects.link(cam)
cam.location=(4.5,-9,4.1)
cam.rotation_euler=(Vector((.03,0,1.22))-cam.location).to_track_quat('-Z','Y').to_euler()
cam_data.type='ORTHO'
scene.camera=cam


def fit_camera(margin=.03, long_side=640 if PREVIEW else 900):
    """Frame exactly what is visible: the pair's geometry and the meadow up to
    the middle of its fade. Image aspect, ortho scale and shift follow, so
    the portrait carries no empty band above the hat."""
    bpy.context.view_layer.update()
    deps=bpy.context.evaluated_depsgraph_get()
    to_cam=cam.matrix_world.inverted()
    points=[]
    triangles=0
    for o in portrait_models:
        if o is None or o.type not in {'MESH','CURVE'}: continue
        ev=o.evaluated_get(deps); me=ev.to_mesh()
        points += [to_cam@(ev.matrix_world@v.co) for v in me.vertices]
        triangles += sum(len(p.vertices)-2 for p in me.polygons)
        ev.to_mesh_clear()
    reach=.47
    for i in range(64):
        t=math.tau*i/64
        points.append(to_cam@Vector((.02+FADE_X*reach*math.cos(t),.08+FADE_Y*reach*math.sin(t),0)))
    xs=[p.x for p in points]; ys=[p.y for p in points]
    w=(max(xs)-min(xs))*(1+margin*2); h=(max(ys)-min(ys))*(1+margin*2)
    scale=max(w,h)
    cam_data.ortho_scale=scale
    cam_data.shift_x=(max(xs)+min(xs))/2/scale
    cam_data.shift_y=(max(ys)+min(ys))/2/scale
    if h>=w:
        scene.render.resolution_y=long_side; scene.render.resolution_x=round(long_side*w/h)
    else:
        scene.render.resolution_x=long_side; scene.render.resolution_y=round(long_side*h/w)
    print('MERCHANT_FRAME',scene.render.resolution_x,'x',scene.render.resolution_y,
          'aspect',round(w/h,3),'triangles',triangles)

fit_camera()
scene.render.filepath=str(ART/'matej-preview.png' if PREVIEW else ASSET/'merchant-matej.png')
# Keep opening the .blend pleasant: hide studio lights and receiver in modelling view.
for o in bpy.context.scene.objects:
    if o.type in {'LIGHT','CAMERA'} or o in shadow_planes: o.hide_set(True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active
            space.shading.type='SOLID'; space.shading.color_type='MATERIAL'
            space.shading.show_cavity=True
            space.overlay.show_floor=False; space.overlay.show_extras=False
            space.region_3d.view_location=Vector((.03,0,1.2))
            space.region_3d.view_distance=4.6
            space.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
            space.region_3d.view_perspective='ORTHO'
bpy.context.view_layer.objects.active=character
bpy.ops.object.select_all(action='DESELECT')
character.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'matej.blend'))
# Export the reusable character and cart; the full roadside scene stays in the .blend.
for o in portrait_models: o.select_set(True)
character.select_set(True); cart.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ART/'matej.glb'),export_format='GLB',use_selection=True,export_apply=True,export_cameras=False,export_lights=False)
# hide_set affects the interactive viewport only; all studio objects still render.
bpy.ops.render.render(write_still=True)
if not PREVIEW:
    (ASSET/'Contents.json').write_text(json.dumps({'images':[{'filename':'merchant-matej.png','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
    print('MERCHANT_ASSET',scene.render.filepath)
print('MERCHANT_DONE',len(MODELS),'editable objects')
