"""Small render helpers for checking the boy in Blender (workbench, orthographic views)."""
import bpy, math
from mathutils import Vector


def setup_workbench(res=(512, 768)):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_cavity = False
    sc.display.shading.show_shadows = False
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    sc.world = sc.world or bpy.data.worlds.new("W")
    sc.display.shading.background_type = "VIEWPORT"
    sc.render.image_settings.file_format = "PNG"


def cam(name, loc, look, ortho=1.9, lens=50):
    c = bpy.data.objects.get(name)
    if c is None:
        c = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        bpy.context.scene.collection.objects.link(c)
    c.location = loc
    d = Vector(look) - Vector(loc)
    c.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if ortho:
        c.data.type = "ORTHO"
        c.data.ortho_scale = ortho
    else:
        c.data.type = "PERSP"
        c.data.lens = lens
    return c


def shoot(path, camobj):
    sc = bpy.context.scene
    sc.camera = camobj
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def views(prefix, h=1.5, top=True):
    """front / side / back / high three-quarter (like the game camera)"""
    m = h * 0.5
    shoot(prefix + "_front.png", cam("cf", (0, -6, m), (0, 0, m), h * 1.15))
    shoot(prefix + "_side.png", cam("cs", (6, 0, m), (0, 0, m), h * 1.15))
    shoot(prefix + "_back.png", cam("cb", (0, 6, m), (0, 0, m), h * 1.15))
    if top:
        p = 60 * math.pi / 180
        dist = 6.0
        shoot(prefix + "_top.png", cam("ct", (dist * math.cos(p) * 0.6, -dist * math.cos(p) * 0.8, m + dist * math.sin(p)), (0, 0, m * 0.8), h * 1.15))


def closeups(prefix, z0, z1, w=0.6):
    m = (z0 + z1) * 0.5
    s = max(z1 - z0, w)
    shoot(prefix + "_cfront.png", cam("cf2", (0, -6, m), (0, 0, m), s))
    shoot(prefix + "_cside.png", cam("cs2", (6, 0, m), (0, 0, m), s))
    shoot(prefix + "_cback.png", cam("cb2", (0, 6, m), (0, 0, m), s))
    shoot(prefix + "_c34.png", cam("c342", (4, -4.5, m + 2.5), (0, 0, m), s))
