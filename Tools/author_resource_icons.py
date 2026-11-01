"""Author the resource icons (coins, wood, bricks, steel, leaf) in Blender.
Run: Blender --background --factory-startup --python this_file -- [--preview]

Same art direction as the town and Matěj (Tools/author_merchant.py): low-poly,
flat shading, single chamfers, flat colours, the town's warm sun and cool
ambient, an orthographic camera. Shapes are chunky so each icon still reads at
14 points, the smallest size the app draws them.
"""
import bpy
import math
import sys
from pathlib import Path
from mathutils import Vector, Euler

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'Pilire' / 'Assets.xcassets'
PREVIEW = '--preview' in sys.argv
SIZE = 192 if PREVIEW else 216   # 72 pt at @3x, the largest the app shows them
OUT = ROOT / 'Art' / 'ResourceIcons'
OUT.mkdir(parents=True, exist_ok=True)


def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for m in list(bpy.data.materials): bpy.data.materials.remove(m)
    for m in list(bpy.data.meshes): bpy.data.meshes.remove(m)


def material(name, color, roughness=.75, metallic=0):
    h = color.lstrip('#')
    rgb = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    linear = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m = bpy.data.materials.new(name); m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*linear, 1)
    bs.inputs['Roughness'].default_value = roughness
    bs.inputs['Metallic'].default_value = metallic
    return m


def finish(o, m, bevel=0):
    o.data.materials.append(m)
    for p in o.data.polygons: p.use_smooth = False
    if bevel:
        b = o.modifiers.new('Single chamfer', 'BEVEL')
        b.width = bevel; b.segments = 1; b.limit_method = 'ANGLE'
    return o


def box(p, size, m, bevel=.04, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=p)
    o = bpy.context.object; o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_euler = rot
    return finish(o, m, bevel)


def cylinder(p, r, depth, m, sides=10, rot=(0, 0, 0), bevel=.03):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=r, depth=depth, location=p, rotation=rot)
    return finish(bpy.context.object, m, bevel)


def prism(p, bottom, top, height, m, rot=(0, 0, 0), bevel=.03):
    """An ingot: a box whose top face is smaller than its base."""
    bx, by = bottom; tx, ty = top
    verts = [(-bx, -by, 0), (bx, -by, 0), (bx, by, 0), (-bx, by, 0),
             (-tx, -ty, height), (tx, -ty, height), (tx, ty, height), (-tx, ty, height)]
    faces = [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    me = bpy.data.meshes.new('ingot'); me.from_pydata(verts, [], faces); me.update()
    o = bpy.data.objects.new('ingot', me); bpy.context.collection.objects.link(o)
    o.location = p; o.rotation_euler = rot
    return finish(o, m, bevel)


def mesh(name, verts, faces, m, bevel=0):
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.update()
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
    return finish(o, m, bevel)


def setup_scene():
    s = bpy.context.scene
    s.render.engine = 'CYCLES'
    s.cycles.samples = 24 if PREVIEW else 96
    s.cycles.use_denoising = True
    s.render.film_transparent = True
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    s.render.resolution_x = s.render.resolution_y = SIZE
    s.world.use_nodes = True
    bg = s.world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (.85, .90, .96, 1)
    bg.inputs['Strength'].default_value = .5
    s.view_settings.view_transform = 'Standard'
    s.view_settings.look = 'None'
    sun = bpy.data.lights.new('Town sun', 'SUN'); sun.energy = 2.6
    sun.color = (1, .96, .88); sun.angle = math.radians(4)
    o = bpy.data.objects.new('Town sun', sun); bpy.context.collection.objects.link(o)
    d = Vector((-.55, -.8, 1.3))
    o.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    cam = bpy.data.objects.new('Icon camera', bpy.data.cameras.new('Icon camera'))
    bpy.context.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    cam.location = (3.2, -6.4, 5.0)
    cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    s.camera = cam
    return cam


def fit(cam, margin=.03):
    """Square framing around every vertex, centred on the shape."""
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    inv = cam.matrix_world.inverted(); pts = []
    for o in bpy.context.scene.objects:
        if o.type != 'MESH': continue
        ev = o.evaluated_get(deps); me = ev.to_mesh()
        pts += [inv @ (ev.matrix_world @ v.co) for v in me.vertices]
        ev.to_mesh_clear()
    xs = [p.x for p in pts]; ys = [p.y for p in pts]
    span = max(max(xs) - min(xs), max(ys) - min(ys)) * (1 + 2 * margin)
    cam.data.ortho_scale = span
    cam.data.shift_x = (max(xs) + min(xs)) / 2 / span
    cam.data.shift_y = (max(ys) + min(ys)) / 2 / span


# MARK: Icons

def coin():
    gold = material('Coin gold', '#E9B949', .45, .25)
    rim = material('Coin rim', '#C9922C', .5, .25)
    relief = material('Pillar relief', '#F6D27A', .45, .2)
    # The face points at the camera, tipped back a little so the edge shows.
    tilt = Euler((math.radians(62), 0, math.radians(27)))
    parts = []
    parts.append(cylinder((0, 0, 0), 1.0, .26, rim, sides=14, bevel=.05))
    parts.append(cylinder((0, 0, .02), .80, .28, gold, sides=14, bevel=.03))
    # A pillar on stepped base: the app's own emblem, struck into the coin.
    z = .16
    parts.append(box((0, -.44, z), (.62, .12, .06), relief, .015))
    parts.append(box((0, -.31, z), (.46, .10, .06), relief, .015))
    parts.append(box((0, .02, z), (.20, .56, .06), relief, .015))
    parts.append(box((0, .36, z), (.38, .10, .06), relief, .015))
    for o in parts:
        o.matrix_world = tilt.to_matrix().to_4x4() @ o.matrix_world


def wood():
    bark = material('Bark', '#8B5A34', .9)
    bark_dark = material('Bark shade', '#734828', .9)
    end = material('End grain', '#E1B47A', .85)
    ring = material('Growth ring', '#C48E55', .85)
    for i, (x, z, m) in enumerate([(-.56, 0, bark), (.56, 0, bark_dark), (0, .92, bark)]):
        rot = (0, 0, 0)
        # Logs lie along Y, ends toward the camera.
        cylinder((x, 0, z), .54, 2.0, m, sides=8, rot=(math.pi/2, 0, 0), bevel=.05)
        for y in (-1.0, 1.0):
            cylinder((x, y, z), .46, .04, end, sides=8, rot=(math.pi/2, 0, 0), bevel=0)
            cylinder((x, y*1.01, z), .22, .04, ring, sides=8, rot=(math.pi/2, 0, 0), bevel=0)
    for o in bpy.context.scene.objects:
        if o.type == 'MESH': o.rotation_euler.rotate(Euler((0, 0, math.radians(-28))))
        if o.type == 'MESH': o.location.rotate(Euler((0, 0, math.radians(-28))))


def bricks():
    a = material('Brick', '#C9643F', .85)
    b = material('Brick warm', '#D5764C', .85)
    c = material('Brick deep', '#B5573A', .85)
    for p, m in [((-.0, -.62, .34), a), ((.0, .62, .34), c), ((0, 0, 1.02), b)]:
        box(p, (2.0, 1.16, .64), m, .07)


def steel():
    body = material('Steel', '#6F7F96', .4, .35)
    top = material('Steel bright', '#93A3B8', .4, .35)
    prism((0, -.5, 0), (1.1, .42), (.86, .28), .46, body, bevel=.04)
    prism((0, .5, 0), (1.1, .42), (.86, .28), .46, top, bevel=.04)
    prism((0, 0, .46), (1.1, .42), (.86, .28), .46, top, rot=(0, 0, math.pi/2), bevel=.04)


def leaf():
    green = material('Leaf', '#6FAE4F', .8)
    vein = material('Leaf vein', '#4E8A37', .8)
    # A faceted leaf: a pointed outline lifted along the midrib.
    outline = [(0, -1.2), (.42, -.85), (.66, -.3), (.62, .3), (.38, .82), (0, 1.25),
               (-.38, .82), (-.62, .3), (-.66, -.3), (-.42, -.85)]
    verts = [(x, y, 0) for x, y in outline] + [(0, y, .16) for y in (-.7, 0, .7)]
    faces = [(0, 1, 10), (1, 2, 10), (2, 3, 11, 10), (3, 4, 12, 11), (4, 5, 12),
             (5, 6, 12), (6, 7, 11, 12), (7, 8, 10, 11), (8, 9, 10), (9, 0, 10)]
    o = mesh('leaf', verts, faces, green)
    s = o.modifiers.new('thickness', 'SOLIDIFY'); s.thickness = .08
    stem = cylinder((0, -1.38, -.02), .06, .5, vein, sides=6, rot=(math.pi/2, 0, 0), bevel=0)
    # Face the camera, lean the tip to the upper right and tilt a little so
    # the facets catch the sun on one side of the midrib.
    face = Vector((3.2, -6.4, 5.0)).to_track_quat('Z', 'Y').to_matrix().to_4x4()
    lean = Euler((math.radians(18), 0, math.radians(-40))).to_matrix().to_4x4()
    for x in (o, stem):
        x.matrix_world = face @ lean @ x.matrix_world


ICONS = {'ResourceCoin': coin, 'ResourceWood': wood, 'ResourceBrick': bricks,
         'ResourceSteel': steel, 'ResourceLeaf': leaf}

for name, build in ICONS.items():
    reset()
    cam = setup_scene()
    build()
    fit(cam)
    if PREVIEW:
        bpy.context.scene.render.filepath = str(OUT / f'{name}-preview.png')
    else:
        folder = ASSETS / f'{name}.imageset'; folder.mkdir(exist_ok=True)
        bpy.context.scene.render.filepath = str(folder / f'{name}.png')
        (folder / 'Contents.json').write_text(
            '{\n  "images" : [\n    {\n      "filename" : "%s.png",\n      "idiom" : "universal"\n    }\n  ],\n'
            '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' % name)
    bpy.ops.render.render(write_still=True)
    print('ICON_DONE', name)
