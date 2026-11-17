# Neon Raid — 3D-модели для Blender 4.2+
# Запуск: blender -b -P neon_raid.py -- bolt   (bolt | bug | spark | core | all)
import bpy, sys, os, math
from math import radians
from mathutils import Vector

OUT = os.path.abspath(os.environ.get("OUT_DIR", "renders"))
SAMPLES = int(os.environ.get("SAMPLES", "48"))
RES = (3840, 2160)

# ---------------------------------------------------------------- материалы
PAL = {
    # имя: (цвет, металл, шероховатость, свечение)
    "STEEL":  ((0.78, 0.80, 0.85), 1.0, 0.22, 0),
    "DARK":   ((0.03, 0.035, 0.06), 0.7, 0.40, 0),
    "GUN":    ((0.10, 0.11, 0.16), 0.9, 0.30, 0),
    "ORANGE": ((1.00, 0.30, 0.00), 0.25, 0.28, 0),
    "RUBBER": ((0.02, 0.02, 0.025), 0.0, 0.85, 0),
    "CYAN":   ((0.02, 0.85, 0.95), 0.0, 0.2, 9),
    "PINK":   ((1.00, 0.08, 0.30), 0.0, 0.2, 9),
    "LIME":   ((0.22, 1.00, 0.08), 0.0, 0.2, 7),
    "GOLD":   ((1.00, 0.80, 0.05), 0.0, 0.2, 10),
    "GLASS":  ((0.30, 0.90, 1.00), 0.0, 0.05, 1.5),
}
MATS = {}

def _set(bsdf, names, val):
    for n in names:
        if n in bsdf.inputs:
            bsdf.inputs[n].default_value = val
            return

def mat(name):
    if name in MATS:
        return MATS[name]
    col, met, rough, em = PAL[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    _set(b, ["Base Color"], (*col, 1))
    _set(b, ["Metallic"], met)
    _set(b, ["Roughness"], rough)
    if name == "ORANGE":
        _set(b, ["Coat Weight", "Clearcoat"], 0.8)
        _set(b, ["Coat Roughness", "Clearcoat Roughness"], 0.08)
    if em:
        _set(b, ["Emission Color", "Emission"], (*col, 1))
        _set(b, ["Emission Strength"], em)
    MATS[name] = m
    return m

# ---------------------------------------------------------------- примитивы
PARTS = []

def _finish(o, color, smooth=False, bevel=0.0):
    o.data.materials.append(mat(color))
    if bevel > 0:
        md = o.modifiers.new("Bevel", "BEVEL")
        md.width = bevel
        md.segments = 3
        md.limit_method = "ANGLE"
        md.angle_limit = radians(40)
    if smooth:
        try:
            bpy.ops.object.shade_smooth_by_angle(angle=radians(40))
        except Exception:
            bpy.ops.object.shade_smooth()
    PARTS.append(o)
    return o

def box(size, color, pos=(0, 0, 0), rot=(0, 0, 0), taper=1.0, bevel=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos, rotation=[radians(a) for a in rot])
    o = bpy.context.active_object
    for v in o.data.vertices:
        t = taper if v.co.z > 0 else 1.0
        v.co.x *= size[0] * t
        v.co.y *= size[1] * t
        v.co.z *= size[2]
    if bevel is None:
        bevel = min(size) * 0.12
    return _finish(o, color, smooth=True, bevel=bevel)

def cyl(r, h, color, pos=(0, 0, 0), rot=(0, 0, 0), r2=None, n=48):
    R = [radians(a) for a in rot]
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=n, radius=r, depth=h, location=pos, rotation=R)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=n, radius1=r, radius2=r2, depth=h, location=pos, rotation=R)
    return _finish(bpy.context.active_object, color, smooth=True, bevel=min(r, h) * 0.08)

def sphere(r, color, pos=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=r, location=pos)
    o = bpy.context.active_object
    o.scale = scale
    return _finish(o, color, smooth=True)

def beam(a, b, r, color):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r, depth=d.length, location=(a + b) / 2)
    o = bpy.context.active_object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    return _finish(o, color, smooth=True, bevel=r * 0.2)

def rivets(xs, y, zs, r=0.025, color="STEEL"):
    for x in xs:
        for z in zs:
            sphere(r, color, (x, y, z))

# ---------------------------------------------------------------- модели (z вверх, перед смотрит в -Y)
def bolt():
    for s in (-1, 1):
        box((0.34, 0.42, 0.2), "DARK", (s * 0.28, -0.05, 0.1))
        box((0.3, 0.1, 0.06), "RUBBER", (s * 0.28, -0.27, 0.04))
        box((0.24, 0.26, 0.55), "STEEL", (s * 0.28, 0, 0.48))
        box((0.04, 0.27, 0.3), "CYAN", (s * 0.405, 0, 0.5), bevel=0.01)
        sphere(0.15, "GUN", (s * 0.28, 0, 0.78))
        box((0.28, 0.3, 0.45), "ORANGE", (s * 0.28, 0, 1.02), taper=1.08)
    box((0.78, 0.44, 0.22), "DARK", (0, 0, 1.28))
    box((0.97, 0.62, 0.76), "ORANGE", (0, 0, 1.75), taper=1.12)
    box((0.52, 0.06, 0.36), "DARK", (0, -0.32, 1.78))
    cyl(0.11, 0.05, "CYAN", (0, -0.355, 1.8), rot=(90, 0, 0))
    cyl(0.15, 0.03, "STEEL", (0, -0.345, 1.8), rot=(90, 0, 0))
    rivets((-0.22, 0.22), -0.355, (1.63, 1.93))
    box((1.0, 0.05, 0.05), "CYAN", (0, -0.33, 1.42), bevel=0.01)  # неоновая полоса
    # джетпак
    box((0.62, 0.32, 0.62), "GUN", (0, 0.45, 1.8))
    box((0.5, 0.04, 0.08), "PINK", (0, 0.62, 1.95), bevel=0.01)
    for s in (-1, 1):
        cyl(0.13, 0.36, "STEEL", (s * 0.2, 0.52, 1.44), r2=0.1)
        cyl(0.1, 0.12, "PINK", (s * 0.2, 0.52, 1.22), r2=0.04)
    # руки
    for s in (-1, 1):
        sphere(0.2, "STEEL", (s * 0.62, 0, 2.0))
        box((0.3, 0.34, 0.12), "ORANGE", (s * 0.64, 0, 2.17), rot=(0, s * -15, 0))
        box((0.22, 0.24, 0.45), "GUN", (s * 0.66, 0, 1.68))
        box((0.27, 0.29, 0.4), "ORANGE", (s * 0.68, -0.05, 1.32), taper=0.9)
    # бластер
    box((0.24, 0.62, 0.24), "DARK", (0.68, -0.38, 1.18))
    box((0.08, 0.4, 0.05), "CYAN", (0.68, -0.4, 1.31), bevel=0.01)
    cyl(0.075, 0.28, "STEEL", (0.68, -0.78, 1.2), rot=(90, 0, 0))
    cyl(0.05, 0.03, "CYAN", (0.68, -0.93, 1.2), rot=(90, 0, 0))
    # голова
    cyl(0.1, 0.18, "GUN", (0, 0, 2.18))
    box((0.64, 0.56, 0.5), "STEEL", (0, 0, 2.48), taper=0.9)
    box((0.54, 0.08, 0.17), "GLASS", (0, -0.27, 2.52), bevel=0.03)
    for s in (-1, 1):
        cyl(0.1, 0.08, "ORANGE", (s * 0.33, 0, 2.48), rot=(0, 90, 0))
        cyl(0.05, 0.09, "CYAN", (s * 0.34, 0, 2.48), rot=(0, 90, 0))
    cyl(0.025, 0.36, "GUN", (0.18, 0.1, 2.88))
    sphere(0.06, "PINK", (0.18, 0.1, 3.08))

def bug():
    sphere(0.55, "DARK", (0, 0.15, 0.95), scale=(1, 1.25, 0.75))
    for y in (-0.05, 0.3, 0.6):
        sphere(0.5, "PINK", (0, y, 1.17), scale=(0.85, 0.22, 0.35))
    sphere(0.38, "GUN", (0, -0.6, 0.95), scale=(1, 1, 0.85))
    sphere(0.15, "PINK", (0, -0.92, 1.0))
    for s in (-1, 1):
        sphere(0.07, "PINK", (s * 0.2, -0.85, 1.15))
        beam((s * 0.12, -0.9, 0.8), (s * 0.06, -1.12, 0.68), 0.035, "STEEL")
        for yy in (-0.4, 0.1, 0.55):
            knee = (s * 1.0, yy * 1.25, 1.3)
            foot = (s * 1.3, yy * 1.45, 0.06)
            beam((s * 0.4, yy, 0.95), knee, 0.05, "STEEL")
            sphere(0.08, "PINK", knee)
            beam(knee, foot, 0.045, "GUN")
            cyl(0.03, 0.12, "DARK", (foot[0], foot[1], 0.06), r2=0.065)
        cyl(0.04, 0.3, "STEEL", (s * 0.35, 0.25, 1.45))
        cyl(0.4, 0.015, "GLASS", (s * 0.38, 0.25, 1.6))
        box((0.8, 0.06, 0.02), "STEEL", (s * 0.38, 0.25, 1.62), rot=(0, 0, 30), bevel=0.005)
        box((0.8, 0.06, 0.02), "STEEL", (s * 0.38, 0.25, 1.62), rot=(0, 0, -60), bevel=0.005)

def spark():
    box((0.72, 2.4, 0.5), "DARK", (0, 0, 0.75), taper=0.75)
    box((0.62, 1.3, 0.35), "ORANGE", (0, -0.2, 1.05), taper=0.7)
    box((0.5, 0.6, 0.22), "GLASS", (0, -0.85, 1.15), rot=(25, 0, 0), taper=0.6, bevel=0.03)
    box((0.46, 0.8, 0.15), "RUBBER", (0, 0.45, 1.15))
    box((0.9, 0.06, 0.06), "STEEL", (0, -0.55, 1.3), bevel=0.01)
    for s in (-1, 1):
        cyl(0.05, 0.18, "RUBBER", (s * 0.45, -0.55, 1.3), rot=(0, 90, 0))
        box((0.05, 2.0, 0.05), "CYAN", (s * 0.37, 0, 0.82), bevel=0.01)
        cyl(0.24, 2.1, "STEEL", (s * 0.5, 0, 0.42), rot=(90, 0, 0))
        sphere(0.24, "STEEL", (s * 0.5, -1.05, 0.42))
        box((0.3, 1.8, 0.04), "LIME", (s * 0.5, 0, 0.17), bevel=0.01)
        box((0.3, 0.25, 0.12), "GUN", (s * 0.32, -0.5, 0.6))
        box((0.3, 0.25, 0.12), "GUN", (s * 0.32, 0.5, 0.6))
        cyl(0.16, 0.7, "GUN", (s * 0.35, 1.2, 0.85), rot=(90, 0, 0), r2=0.2)
        cyl(0.13, 0.05, "PINK", (s * 0.35, 1.56, 0.85), rot=(90, 0, 0))
    box((0.06, 0.4, 0.4), "ORANGE", (0, 1.1, 1.3), rot=(-20, 0, 0), bevel=0.01)
    cyl(0.08, 0.05, "GOLD", (0, -1.22, 0.8), rot=(90, 0, 0))

def core():
    box((0.9, 0.9, 0.9), "GUN", (0, 0, 0.5))
    for z in (0.08, 0.92):
        box((0.98, 0.98, 0.12), "ORANGE", (0, 0, z))
    for x in (-0.45, 0.45):
        for y in (-0.45, 0.45):
            box((0.12, 0.12, 0.9), "ORANGE", (x, y, 0.5))
    for s in (-1, 1):
        box((0.5, 0.04, 0.5), "CYAN", (0, s * 0.46, 0.5), bevel=0.02)
        box((0.04, 0.5, 0.5), "CYAN", (s * 0.46, 0, 0.5), bevel=0.02)
    cyl(0.18, 0.12, "STEEL", (0, 0, 1.03))
    sphere(0.28, "LIME", (0, 0, 1.38))
    cyl(0.4, 0.02, "LIME", (0, 0, 1.38), rot=(70, 0, 20))

MODELS = {"bolt": bolt, "bug": bug, "spark": spark, "core": core}
VIEWS = [("front", 0, 8), ("back", 180, 8), ("left", -90, 8),
         ("right", 90, 8), ("top", 0, 89), ("three_quarter", -35, 22)]

# ---------------------------------------------------------------- сцена
def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Punchy"
    except Exception:
        sc.view_settings.view_transform = "Filmic"
    # фон
    w = bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.012, 0.008, 0.03, 1)
    bg.inputs[1].default_value = 1.0
    # пол
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    fl = bpy.context.active_object
    fm = bpy.data.materials.new("Floor")
    fm.use_nodes = True
    b = fm.node_tree.nodes["Principled BSDF"]
    _set(b, ["Base Color"], (0.015, 0.012, 0.03, 1))
    _set(b, ["Roughness"], 0.25)
    _set(b, ["Metallic"], 0.3)
    fl.data.materials.append(fm)
    # свет
    def light(name, typ, loc, energy, color, size=3):
        d = bpy.data.lights.new(name, typ)
        d.energy = energy
        d.color = color
        if typ == "AREA":
            d.size = size
        o = bpy.data.objects.new(name, d)
        sc.collection.objects.link(o)
        o.location = loc
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = (Vector((0, 0, 1.2)) - Vector(loc)).to_track_quat("-Z", "Y")
    light("Key", "AREA", (-4, -6, 7), 1800, (1, 0.96, 0.92), 4)
    light("RimCyan", "AREA", (6, 5, 4), 1200, (0.2, 0.8, 1), 3)
    light("RimPink", "AREA", (-6, 5, 3), 1000, (1, 0.2, 0.5), 3)
    light("Fill", "AREA", (5, -6, 2), 400, (0.7, 0.75, 1), 5)
    light("Top", "AREA", (0, 0, 9), 600, (1, 1, 1), 6)
    # камера
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.clip_end = 200
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    # свечение неона (композитинг)
    try:
        sc.use_nodes = True
        nt = sc.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        rl = nt.nodes.new("CompositorNodeRLayers")
        gl = nt.nodes.new("CompositorNodeGlare")
        gl.glare_type = "FOG_GLOW"
        gl.quality = "HIGH"
        gl.threshold = 1.0
        gl.size = 8
        co = nt.nodes.new("CompositorNodeComposite")
        nt.links.new(rl.outputs["Image"], gl.inputs["Image"])
        nt.links.new(gl.outputs["Image"], co.inputs["Image"])
    except Exception as e:
        print("glare skipped:", e)
    return cam

def frame(cam, az, el):
    az, el = radians(az), radians(el)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    pts = []
    for o in PARTS:
        for c in o.bound_box:
            pts.append(o.matrix_world @ Vector(c))
    mn = Vector([min(p[i] for p in pts) for i in range(3)])
    mx = Vector([max(p[i] for p in pts) for i in range(3)])
    center = (mn + mx) / 2
    cam.location = center + d * 30
    cam.rotation_mode = "QUATERNION"
    q = (-d).to_track_quat("-Z", "Y")
    cam.rotation_quaternion = q
    right = q @ Vector((1, 0, 0))
    up = q @ Vector((0, 1, 0))
    w = max(abs((p - center).dot(right)) for p in pts) * 2
    h = max(abs((p - center).dot(up)) for p in pts) * 2
    cam.data.ortho_scale = max(w, h * RES[0] / RES[1]) * 1.25

def build(name):
    global PARTS
    PARTS = []
    cam = setup_scene()
    MODELS[name]()
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    for o in PARTS:
        for c in o.users_collection:
            c.objects.unlink(o)
        col.objects.link(o)
    os.makedirs(OUT, exist_ok=True)
    # файлы модели
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, f"{name}.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    for o in PARTS:
        o.select_set(True)
    try:
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"{name}.glb"),
                                  use_selection=True, export_apply=True)
    except Exception as e:
        print("glb export failed:", e)
    # рендеры
    for vname, az, el in VIEWS:
        frame(cam, az, el)
        bpy.context.scene.render.filepath = os.path.join(OUT, f"{name}_{vname}_4K.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", name, vname, flush=True)

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
    targets = list(MODELS) if argv[0] == "all" else argv
    for t in targets:
        build(t)
