"""Builds the v6 boy: MPFB2 (MakeHuman, CC0) teen body + game_engine skeleton, clothes / hair /
flip-flops as offset shells of the body, a lathed straw hat on the head bone.

blender -b --python art/boy/build_boy.py -- [--render DIR] [--save FILE.blend]
"""
import bpy, bmesh, sys, os, math, random
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(__file__))
import shoulder
import hair as hairkit
import fabric
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DATA = os.path.expanduser("~/.config/blender/4.5/mpfb/data/")
HEAD_SCALE = 1.08

# albedo (linear-ish sRGB values; Godot overrides the materials but keeps these as the base colors)
COLORS = {
    "skin": (0.93, 0.74, 0.60),
    "tank": (0.95, 0.94, 0.90),
    "vest": (0.80, 0.22, 0.18),
    "shorts": (0.97, 0.80, 0.30),
    "hair": (0.24, 0.16, 0.11),
    "sandal": (0.30, 0.55, 0.62),
    "strap": (0.95, 0.93, 0.88),
    "hat": (0.90, 0.78, 0.52),
    "band": (0.75, 0.20, 0.17),
    "lens": (0.06, 0.07, 0.09),
    "stone": (0.52, 0.52, 0.50),
    "cord": (0.93, 0.91, 0.85),
}


def arg(name, default=None):
    return ARGS[ARGS.index(name) + 1] if name in ARGS else default


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    c = COLORS[name]
    m.diffuse_color = (c[0], c[1], c[2], 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    return m


# ------------------------------------------------------------------ body

def make_body():
    macro = TargetService.get_default_macro_info_dict()
    macro.update({"gender": 1.0, "age": 0.24, "muscle": 0.45, "weight": 0.36, "proportions": 0.7, "height": 0.5})
    macro["race"] = {"asian": 0.5, "caucasian": 0.4, "african": 0.1}
    base = HumanService.create_human(macro_detail_dict=macro, scale=0.1)
    rig = HumanService.add_builtin_rig(base, "game_engine")
    px = HumanService.add_mhclo_asset(DATA + "proxymeshes/male1591/male1591.proxy", base, asset_type="Proxymeshes", subdiv_levels=0)
    bpy.data.objects.remove(base)
    rig.name = rig.data.name = "BoyRig"
    px.name = "Body"
    # bake one subdivision level into the mesh (weights are interpolated)
    bpy.context.view_layer.objects.active = px
    for m in list(px.modifiers):
        if m.type != "ARMATURE":
            px.modifiers.remove(m)
    sub = px.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    bpy.ops.object.modifier_move_to_index(modifier="sub", index=0)
    bpy.ops.object.modifier_apply(modifier="sub")
    px.data.materials.clear()
    px.data.materials.append(material("skin"))
    return rig, px


def weight(obj, v, group):
    g = obj.vertex_groups.get(group)
    if g is None:
        return 0.0
    for e in v.groups:
        if e.group == g.index:
            return e.weight
    return 0.0


def close_eyes(rig, body):
    """the proxy has open eye sockets and mouth (MakeHuman eyeballs / teeth go there); cap them,
    the shader draws eyes and mouth"""
    hz = rig.data.bones["head"].head_local.z
    bm = bmesh.new()
    bm.from_mesh(body.data)
    edges = [e for e in bm.edges if e.is_boundary and all(v.co.z > hz - 0.06 for v in e.verts)]
    res = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    centres = []
    for f in res["faces"]:
        if f.calc_center_median().z > hz:
            centres += bmesh.ops.poke(bm, faces=[f])["verts"]
        else:       # the mouth slit: closed, the shader draws the mouth
            bmesh.ops.triangulate(bm, faces=[f])
    bm.verts.index_update()
    body["eye_idx"] = [v.index for v in centres]
    # settle the caps a little into the sockets so the lids keep their shape
    bm.normal_update()
    bm.to_mesh(body.data)
    bm.free()
    print("EYE CAPS", len(res["faces"]))


def scale_head(rig, body):
    """slightly bigger head (younger look) — scaled about the neck by the head weight"""
    head = rig.data.bones["head"]
    piv = Vector(head.head_local)
    for v in body.data.vertices:
        w = weight(body, v, "head") + 0.5 * weight(body, v, "neck_01") * (1.0 if v.co.z > piv.z - 0.03 else 0.0)
        w = min(w, 1.0)
        if w > 0:
            v.co = piv + (v.co - piv) * (1.0 + (HEAD_SCALE - 1.0) * w)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones["head"]
    eb.tail = piv + (eb.tail - piv) * HEAD_SCALE
    bpy.ops.object.mode_set(mode="OBJECT")


# ------------------------------------------------------------------ shells

HUG_RINGS = (0.62, 0.76, 0.88, 0.96)


def shell(body, name, select, offset, mat, solid=0.0, relax=8, hug=None, resample=False, cloth=None):
    """copy the body faces where select(face) is true, smooth the cut edge along the body surface,
    push the copy out by offset(co, n); boundary vertices where hug(co) sit closer to the body.
    cloth (fabric.Cloth) adds finer faces where folds go, the folds / hems themselves and the
    per-vertex hem, seam and sway data for shaders/cloth.gdshader"""
    from mathutils.bvhtree import BVHTree
    src = bmesh.new()
    src.from_mesh(body.data)
    bvh = BVHTree.FromBMesh(src)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    keepf = set(f for f in bm.faces if select(f))
    kill = [f for f in bm.faces if f not in keepf]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    # drop single faces hanging on by a corner (the selection is per face)
    for _ in range(2):
        lone = [f for f in bm.faces if sum(1 for e in f.edges if e.is_boundary) >= 3]
        bmesh.ops.delete(bm, geom=lone, context="FACES")
    if cloth:
        cloth.subdivide(bm, bvh, src)
    # relax the boundary: average along the cut, then snap back onto the body
    bnd = [v for v in bm.verts if any(e.is_boundary for e in v.link_edges)]
    for _ in range(relax):
        new = {}
        for v in bnd:
            nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(nb) == 2:
                new[v] = v.co * 0.4 + (nb[0].co + nb[1].co) * 0.3
        for v, co in new.items():
            hit = bvh.find_nearest(co)
            v.co = hit[0] if hit[0] is not None else co
    # pull the inner rings a little so the cut faces don't get squashed (more rings on the finer
    # cloth faces, where the relaxed edge travels further in edge lengths)
    inner = set()
    ring = set(bnd)
    for _ in range(3 if cloth else 1):
        nxt = set()
        for v in ring:
            for e in v.link_edges:
                o = e.other_vert(v)
                if o not in bnd and o not in inner:
                    nxt.add(o)
        inner |= nxt
        ring = nxt
    for _ in range(3 if cloth else 1):
        for v in inner:
            nb = [e.other_vert(v) for e in v.link_edges]
            co = v.co * 0.5 + sum((n.co for n in nb), Vector()) / len(nb) * 0.5
            hit = bvh.find_nearest(co)
            v.co = hit[0] if hit[0] is not None else co
    # resample: the relaxed vertices take the skin weights of where they slid to, so the skin under
    # a long-relaxed edge can't poke through it in strong poses
    from mathutils.interpolate import poly_3d_calc
    src.faces.ensure_lookup_table()
    dl_src = src.verts.layers.deform.active
    dl = bm.verts.layers.deform.active
    if resample and dl_src is not None and dl is not None:
        for v in set(bnd) | inner:
            loc, n, fi, d = bvh.find_nearest(v.co)
            if fi is None:
                continue
            fv = src.faces[fi].verts
            bw = poly_3d_calc([u.co for u in fv], loc)
            acc = {}
            for u, w in zip(fv, bw):
                for g, x in u[dl_src].items():
                    acc[g] = acc.get(g, 0.0) + w * x
            dv = v[dl]
            dv.clear()
            for g, x in acc.items():
                if x > 1e-4:
                    dv[g] = x
    bm.normal_update()
    # edges that should lie close on the skin (armholes): offset eased in over a few rings
    ease = {}
    if hug:
        ring = [v for v in bnd if hug(v.co)]
        for k in HUG_RINGS:
            nxt = []
            for v in ring:
                if v not in ease:
                    ease[v] = k
                    nxt += [e.other_vert(v) for e in v.link_edges]
            ring = [v for v in nxt if v not in ease]
    ed = {}
    bm.verts.index_update()
    ease = {v.index: k for v, k in ease.items()}
    if cloth:
        ed = {v.index: d for v, d in cloth.edge_distance(bm).items()}
        cloth.store(bm, ed)
    bm.verts.ensure_lookup_table()
    moves = []
    folds = {}
    for v in bm.verts:
        hit = bvh.find_nearest(v.co)
        n = hit[1] if hit[1] is not None else v.normal
        n = (n + v.normal).normalized()
        d = offset(v.co, n) * ease.get(v.index, 1.0)
        if cloth:
            folds[v.index] = cloth.fold(v.co, n, ed[v.index])
            d += folds[v.index]
        moves.append(n * d)
    if cloth:
        cloth.cavity(bm, folds)
        bm.verts.ensure_lookup_table()
    for v, m in zip(bm.verts, moves):
        v.co = v.co + m
    bm.normal_update()
    if cloth:
        for v in bm.verts:
            ns = [f.normal for f in v.link_faces]
            if ns and min(a.dot(b) for a in ns for b in ns) < -0.3:
                print("WARN folded-over cloth face", name, tuple(round(c, 3) for c in v.co))
    src.free()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = body.parent
    for g in body.vertex_groups:
        ob.vertex_groups.new(name=g.name)
    # vertex groups were carried in the mesh deform layer; re-link armature modifier
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = body.parent
    me.materials.clear()
    me.materials.append(material(mat))
    for p in me.polygons:
        p.use_smooth = True
    if solid > 0:
        s = ob.modifiers.new("solid", "SOLIDIFY")
        s.thickness = solid
        s.offset = 1.0
        s.use_rim = True
        # even offset multiplies the thickness where panels meet at a sharp angle (the shorts' crotch)
        s.use_even_offset = cloth is None
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_move_to_index(modifier="solid", index=0)
        bpy.ops.object.modifier_apply(modifier="solid")
    return ob


def fc(f):
    return f.calc_center_median()


def arm_weights(body):
    """per-vertex arm weight (MPFB weights, before the shoulder re-split) — places the armholes"""
    arm = {}
    groups = {g.index: g.name for g in body.vertex_groups}
    for v in body.data.vertices:
        a = 0.0
        for e in v.groups:
            n = groups[e.group]
            if n.split("_")[0] in ("upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky"):
                a += e.weight
        arm[v.index] = a
    return arm


def build(rig, body, arm):
    J = {b.name: Vector(b.head_local) for b in rig.data.bones}
    neck_z = J["neck_01"].z
    sh_x = J["upperarm_l"].x
    knee_z = J["calf_l"].z
    hip_z = J["pelvis"].z

    def favg(f, d):
        return sum(d[v.index] for v in f.verts) / len(f.verts)

    # ---- tank top
    def tank_sel(f):
        c = fc(f)
        if favg(f, arm) > 0.22:
            return False
        if c.z < hip_z + 0.035 or c.z > neck_z + 0.02:
            return False
        ax = abs(c.x)
        # armhole: a little deeper and wider than the vest's, so its edge stays tucked under the
        # vest and the vest armhole opens straight onto skin (no white ring round the arm)
        if c.z > neck_z - 0.145 and ax > sh_x - 0.06:
            return False
        # scoop neck (front deeper than back)
        if c.y < 0 and c.z > neck_z - 0.075 and ax < 0.07:
            return False
        if c.y >= 0 and c.z > neck_z - 0.03 and ax < 0.065:
            return False
        if c.z > neck_z - 0.01:
            return False
        return True

    B = fabric.Body(body, J)

    def under_vest(co):
        """1 where the vest covers this point of the tank (its opening and armholes are open)"""
        if co.z < hip_z + 0.085 or co.z > neck_z:
            return 0.0
        ax = abs(co.x)
        if co.z > neck_z - 0.13 and ax > sh_x - 0.05:
            return 0.0
        if co.y < 0 and ax < 0.028 + max(0.0, co.z - (neck_z - 0.16)) * 0.45 + 0.006:
            return 0.0
        return 1.0

    def tank_off(co, n):
        # thinner under the vest's armholes, which hug the skin
        return 0.0042 - 0.0016 * fabric.ss(neck_z - 0.17, neck_z - 0.12, co.z) * fabric.ss(sh_x - 0.11, sh_x - 0.07, abs(co.x))

    tank = shell(body, "Tank", tank_sel, tank_off, "tank", solid=0.0008, relax=20, resample=True,
                 cloth=fabric.tank(J, B, under_vest))

    # ---- open red vest
    def vest_sel(f):
        c = fc(f)
        if favg(f, arm) > 0.3:
            return False
        if c.z < hip_z + 0.085 or c.z > neck_z + 0.0:
            return False
        ax = abs(c.x)
        if c.z > neck_z - 0.13 and ax > sh_x - 0.05:
            return False
        if c.y < 0:
            # open front, lapels widening towards the shoulders
            gap = 0.028 + max(0.0, c.z - (neck_z - 0.16)) * 0.45
            if ax < gap:
                return False
        if c.y >= 0 and c.z > neck_z - 0.035 and ax < 0.07:
            return False
        return True

    vest = shell(body, "Vest", vest_sel, lambda co, n: 0.0085 + max(0.0, (hip_z + 0.2) - co.z) * 0.03, "vest", solid=0.0035, relax=24,
                 hug=lambda co: co.z > neck_z - 0.09 and abs(co.x) > sh_x - 0.055, cloth=fabric.vest(J, B))

    # ---- yellow shorts, flared hem
    hem_z = knee_z + 0.11

    def shorts_sel(f):
        c = fc(f)
        if c.z < hem_z or c.z > hip_z + 0.095:
            return False
        if favg(f, arm) > 0.1:
            return False
        return True

    def shorts_off(co, n):
        flare = max(0.0, (hem_z + 0.12) - co.z) / 0.12
        return 0.0085 + 0.022 * flare * flare

    shorts = shell(body, "Shorts", shorts_sel, shorts_off, "shorts", solid=0.0025,
                   cloth=fabric.shorts(J, B, hem_z, hip_z + 0.095))
    fabric.drawstring(rig, body, shorts, hip_z + 0.095, material("cord"), _tube)

    # ---- the v16 hair volume: only sizes the hat now (hair.py grows the hair cards under it)
    head_top = max(v.co.z for v in body.data.vertices)
    hc = J["head"]

    def hair_sel(f):
        c = fc(f)
        if c.z < hc.z + 0.03:
            return False
        if c.y < hc.y - 0.02 and c.z < head_top - 0.075:      # face
            return False
        if abs(c.x) > 0.055 and c.z < hc.z + 0.085 and c.y < hc.y + 0.02:  # ears / temples
            return False
        return True

    rnd = random.Random(5)
    noise = {}

    def hair_off(co, n):
        key = (round(co.x, 3), round(co.y, 3), round(co.z, 3))
        if key not in noise:
            noise[key] = rnd.random()
        k = noise[key]
        up = max(0.0, co.z - (hc.z + 0.05)) / 0.12
        return 0.009 + 0.004 * up + 0.005 * k

    envelope = shell(body, "HairEnvelope", hair_sel, hair_off, "hair", solid=0.006)

    # remove body faces hidden under the tank top / shorts (keeps the tri count down, no poke-through)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    kill = []
    for f in bm.faces:
        c = fc(f)
        if favg(f, arm) > 0.05:
            continue
        if hip_z + 0.06 < c.z < neck_z - 0.12 and abs(c.x) < sh_x - 0.07:
            kill.append(f)
        elif hem_z + 0.07 < c.z < hip_z + 0.06:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(body.data)
    bm.free()

    sandals(rig, body)
    hat_info = hat(rig, body, envelope, head_top)
    bpy.data.objects.remove(envelope)
    hair = hairkit.build(rig, body, hat_info, material("hair"))
    glasses(rig, body)
    stone(rig)
    return [tank, vest, shorts, hair]


def sandals(rig, body):
    for side in ("l", "r"):
        ankle = Vector(rig.data.bones["foot_" + side].head_local)
        ball = Vector(rig.data.bones["ball_" + side].head_local)
        toe = Vector(rig.data.bones["ball_" + side].tail_local)
        pts = [v.co.copy() for v in body.data.vertices if v.co.z < 0.035 and (v.co.xy - ankle.xy).length < 0.2 and v.co.x * ankle.x > 0]
        # outline in the foot's own frame: axis along heel->toe
        ax = (toe - ankle)
        ax.z = 0
        ax.normalize()
        sd = Vector((-ax.y, ax.x, 0))
        us = [(p - ankle).dot(ax) for p in pts]
        vs = [(p - ankle).dot(sd) for p in pts]
        u0, u1 = min(us) - 0.008, max(us) + 0.01
        bm = bmesh.new()
        ring = []
        n = 20
        for i in range(n):
            t = i / n * 2 * math.pi
            u = (u0 + u1) * 0.5 + (u1 - u0) * 0.5 * math.cos(t)
            # width follows the foot: narrow heel, wide ball
            k = (u - u0) / (u1 - u0)
            near = [vv for uu, vv in zip(us, vs) if abs(uu - u) < 0.02] or [0.0]
            half = (max(near) - min(near)) * 0.5 + 0.009
            mid = (max(near) + min(near)) * 0.5
            half = max(half, 0.022) if 0.15 < k < 0.95 else max(half, 0.016)
            v = mid + half * math.sin(t)
            p = ankle + ax * u + sd * v
            ring.append(Vector((p.x, p.y, -0.012)))
        top = [bm.verts.new((p.x, p.y, 0.003)) for p in ring]
        bot = [bm.verts.new((p.x, p.y, -0.012)) for p in ring]
        bm.faces.new(top)
        bm.faces.new(list(reversed(bot)))
        for i in range(n):
            bm.faces.new([top[i], top[(i + 1) % n], bot[(i + 1) % n], bot[i]])
        sole = bpy.data.meshes.new("Sandal_" + side)
        bm.to_mesh(sole)
        bm.free()
        ob = bpy.data.objects.new("Sandal_" + side, sole)
        bpy.context.scene.collection.objects.link(ob)
        sole.materials.append(material("sandal"))
        # thong strap: toe gap -> both sides of the instep
        gap = ankle + ax * (ball - ankle).dot(ax) * 1.18 + sd * (0.012 if side == "l" else -0.012)
        gap.z = 0.012
        top_pt = ankle + ax * (ball - ankle).dot(ax) * 0.55
        sm = bpy.data.meshes.new("Strap_" + side)
        bm = bmesh.new()
        for sgn in (-1, 1):
            # find the side of the foot surface at the instep
            side_pt = top_pt + sd * sgn * 0.04
            side_pt.z = 0.008
            surf = [v.co for v in body.data.vertices if (v.co - top_pt).xy.length < 0.06 and v.co.z < 0.1 and v.co.x * ankle.x > 0]
            ztop = max([p.z for p in surf if abs((p - top_pt).dot(ax)) < 0.015] + [0.05])
            mid = top_pt + sd * sgn * 0.022
            mid.z = ztop + 0.004
            path = [gap, (gap + mid) * 0.5 + Vector((0, 0, 0.012)), mid, side_pt]
            _tube(bm, path, 0.0045)
        bm.to_mesh(sm)
        bm.free()
        so = bpy.data.objects.new("Strap_" + side, sm)
        bpy.context.scene.collection.objects.link(so)
        sm.materials.append(material("strap"))
        for o in (ob, so):
            o.parent = rig
            for p in o.data.polygons:
                p.use_smooth = True
            _rigid_foot(o, rig, side)


def _tube(bm, path, r, seg=6):
    rings = []
    for i, p in enumerate(path):
        d = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized()
        b = d.cross(a)
        rings.append([bm.verts.new(p + (a * math.cos(t) + b * math.sin(t)) * r) for t in [j / seg * 2 * math.pi for j in range(seg)]])
    for i in range(len(rings) - 1):
        for j in range(seg):
            bm.faces.new([rings[i][j], rings[i][(j + 1) % seg], rings[i + 1][(j + 1) % seg], rings[i + 1][j]])


def _rigid_foot(o, rig, side):
    ball = Vector(rig.data.bones["ball_" + side].head_local)
    ankle = Vector(rig.data.bones["foot_" + side].head_local)
    ax = (ball - ankle)
    ax.z = 0
    L = ax.length
    ax.normalize()
    gf = o.vertex_groups.new(name="foot_" + side)
    gb = o.vertex_groups.new(name="ball_" + side)
    for v in o.data.vertices:
        u = (v.co - ankle).dot(ax) / L
        k = min(max((u - 0.9) / 0.25, 0.0), 1.0)
        if k < 1:
            gf.add([v.index], 1.0 - k, "REPLACE")
        if k > 0:
            gb.add([v.index], k, "REPLACE")
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = rig


def hat(rig, body, hair, head_top):
    """woven straw hat: lathed crown + wide, slightly drooping brim, red band. Rigid on the head bone."""
    hb = rig.data.bones["head"]
    base_z = head_top - 0.062
    hv = [v.co for v in hair.data.vertices]
    ring = [p for p in hv if base_z - 0.01 < p.z < base_z + 0.04] + [v.co for v in body.data.vertices if abs(v.co.z - base_z) < 0.01]
    rx = max(abs(p.x) for p in ring) + 0.004
    cy = (max(p.y for p in ring) + min(p.y for p in ring)) * 0.5
    ry = (max(p.y for p in ring) - min(p.y for p in ring)) * 0.5 + 0.004
    ch = max(p.z for p in hv) + 0.004 - base_z
    prof = [  # (radius scale, z) from the crown top down to the brim edge
        (0.0, ch), (0.5, ch * 0.97), (0.82, ch * 0.86), (0.97, ch * 0.62), (1.0, ch * 0.3), (1.01, 0.0),
        (1.06, -0.003), (1.3, -0.005), (1.55, -0.011), (1.75, -0.02), (1.82, -0.025),
    ]
    # pushed back on the head (pivot near the back of the band) so the high game camera sees the face
    tilt = Matrix.Rotation(math.radians(-13.0), 4, "X")
    piv = Vector((0.0, cy + ry * 0.8, base_z))
    seg = 28
    bm = bmesh.new()
    rings = []
    for (s, z) in prof:
        r = []
        for j in range(seg):
            t = j / seg * 2 * math.pi
            p = Vector((math.cos(t) * rx * s, cy + math.sin(t) * ry * s, base_z + z))
            r.append(bm.verts.new(piv + tilt @ (p - piv)))
        rings.append(r)
    for i in range(len(rings) - 1):
        for j in range(seg):
            bm.faces.new([rings[i][j], rings[i][(j + 1) % seg], rings[i + 1][(j + 1) % seg], rings[i + 1][j]])
    me = bpy.data.meshes.new("Hat")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material("hat"))
    me.materials.append(material("band"))
    for p in me.polygons:
        p.use_smooth = True
        if p.index // seg == 4:      # the ring between 0.3 * ch and the brim root
            p.material_index = 1
    sol = bpy.data.objects.new("Hat", me)
    bpy.context.scene.collection.objects.link(sol)
    s = sol.modifiers.new("solid", "SOLIDIFY")
    s.thickness = 0.004
    s.offset = 0.0
    bpy.context.view_layer.objects.active = sol
    bpy.ops.object.modifier_apply(modifier="solid")
    # straw weave coordinates (radial / angular) for the Godot shader
    uv = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co
        d = Vector((co.x, co.y - cy))
        uv.data[loop.index].uv = (math.atan2(d.y, d.x) / (2 * math.pi) + 0.5, d.length + max(0.0, co.z - base_z) * 1.0)
    # parent to the head bone, keeping the rest placement
    _bone_child(sol, rig, "head")
    return {"piv": piv, "tilt": -13.0, "cy": cy, "rx": rx, "ry": ry, "base_z": base_z, "prof": prof}


def _bone_child(ob, rig, bone):
    ob.parent = rig
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    b = rig.data.bones[bone]
    ob.matrix_parent_inverse = (rig.matrix_world @ b.matrix_local @ Matrix.Translation((0, b.length, 0))).inverted()


def glasses(rig, body):
    """round sunglasses (shown while sunbathing)"""
    bm = bmesh.new()
    eye_z = rig.data.bones["head"].head_local.z + 0.040 * HEAD_SCALE / 1.08
    fy = {}
    for sx in (1, -1):
        near = [v.co for v in body.data.vertices if abs(v.co.x - 0.031 * sx) < 0.012 and abs(v.co.z - eye_z) < 0.012]
        fy[sx] = min(p.y for p in near) - 0.006
    lens_r = 0.0135
    for sx in (1, -1):
        c = Vector((0.032 * sx, fy[sx], eye_z))
        bmesh.ops.create_circle(bm, cap_ends=True, segments=14, radius=lens_r,
                                matrix=Matrix.Translation(c) @ Matrix.Rotation(math.pi / 2, 4, "X"))
        _tube(bm, [c + Vector((0.0135 * sx, 0.0, 0.003)), c + Vector((0.035 * sx, 0.03, 0.006)), c + Vector((0.04 * sx, 0.075, 0.0))], 0.0018, 4)
    _tube(bm, [Vector((0.019, fy[1], eye_z + 0.003)), Vector((0.0, min(fy.values()) - 0.002, eye_z + 0.006)), Vector((-0.019, fy[-1], eye_z + 0.003))], 0.0018, 4)
    me = bpy.data.meshes.new("Glasses")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material("lens"))
    ob = bpy.data.objects.new("Glasses", me)
    bpy.context.scene.collection.objects.link(ob)
    s = ob.modifiers.new("solid", "SOLIDIFY")
    s.thickness = 0.002
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="solid")
    _bone_child(ob, rig, "head")


def stone(rig):
    """the skipping stone held in the right palm"""
    h = Vector(rig.data.bones["hand_r"].head_local)
    m = Vector(rig.data.bones["middle_01_r"].head_local)
    i = Vector(rig.data.bones["index_01_r"].head_local)
    p = Vector(rig.data.bones["pinky_01_r"].head_local)
    c = h * 0.3 + m * 0.7
    across = (i - p).normalized()
    along = (m - h).normalized()
    palm_n = across.cross(along).normalized()
    c = c + palm_n * 0.018
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=1.0)
    rot = Matrix((across, along, palm_n)).transposed().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(c) @ rot @ Matrix.Diagonal((0.026, 0.022, 0.009, 1.0)), verts=bm.verts)
    me = bpy.data.meshes.new("Stone")
    bm.to_mesh(me)
    bm.free()
    for p_ in me.polygons:
        p_.use_smooth = True
    me.materials.append(material("stone"))
    ob = bpy.data.objects.new("Stone", me)
    bpy.context.scene.collection.objects.link(ob)
    _bone_child(ob, rig, "hand_r")


def face_uv2(rig, body):
    """front projection of the head into UV2 (the shader draws eyes / brows / mouth there);
    (5, 5) marks non-face loops until export turns that into a vertex-colour mask"""
    hb = rig.data.bones["head"]
    me = body.data
    while len(me.uv_layers) < 2:
        me.uv_layers.new(name="Face")
    face = me.uv_layers[1]
    face.name = "Face"
    hw = {v.index: weight(body, v, "head") for v in me.vertices}
    hc = Vector(hb.head_local)
    for loop in me.loops:
        v = me.vertices[loop.vertex_index]
        if hw[v.index] > 0.5 and v.normal.y < 0.2:
            face.data[loop.index].uv = (v.co.x, v.co.z - hc.z)
        else:
            face.data[loop.index].uv = (5.0, 5.0)
    eyes = [me.vertices[i].co for i in body["eye_idx"]]
    body["eyes_uv"] = [(e.x, e.z - hc.z) for e in eyes]
    print("EYES UV", body["eyes_uv"][:])


def main():
    clear()
    rig, body = make_body()
    close_eyes(rig, body)
    scale_head(rig, body)
    face_uv2(rig, body)
    arm = arm_weights(body)
    shoulder.sculpt(rig, body)
    shoulder.add_helpers(rig)
    shoulder.reweight(rig, body)
    parts = build(rig, body, arm)
    print("TRIS", {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == "MESH"})
    save = arg("--save")
    if save:
        bpy.ops.wm.save_as_mainfile(filepath=save)
    rd = arg("--render")
    if rd:
        import rtools
        rtools.setup_workbench((700, 900))
        rtools.views(rd + "/boy", 1.5)
        rtools.closeups(rd + "/boy", 0.7, 1.5)
    out = arg("--export")
    if out:
        import export_boy
        export_boy.export(rig, out)
        if save:
            bpy.ops.wm.save_as_mainfile(filepath=save.replace(".blend", "_baked.blend"))


main()
