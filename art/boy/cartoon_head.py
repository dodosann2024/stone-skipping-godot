"""v22 dedicated stylized child head (Pixar / Animal-Crossing-like).

A round skull, soft chin, tiny button nose, low-set big eyes, small ears and a slim neck —
built as its own mesh (BoyHead), weighted fully to the head bone, with simple shape keys for
blink / smile / open / frown / press / squint / brows. MakeHuman's head is cut off the body at
the neck so clothes and the body stay as they are. Hair is a smooth helmet with a few soft bang
clumps (material "hair") on the same object. Eyes are separate UV spheres parented to the head bone.
"""
import bpy, bmesh, math, os, random
import numpy as np
from mathutils import Vector, Matrix

# relative to the body's head after HEAD_SCALE: a little bigger for chibi appeal
CHIBI = 1.15
SEED = 22


def _ss(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _weight(obj, v, group):
    g = obj.vertex_groups.get(group)
    if g is None:
        return 0.0
    for e in v.groups:
        if e.group == g.index:
            return e.weight
    return 0.0


def cut_body_head(rig, body):
    """remove the MakeHuman head / face; keep only a slim neck stump under the head joint"""
    hb = rig.data.bones["head"]
    piv = Vector(hb.head_local)
    hg = body.vertex_groups["head"].index if "head" in body.vertex_groups else None
    ng = body.vertex_groups["neck_01"].index if "neck_01" in body.vertex_groups else None
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    dl = bm.verts.layers.deform.active
    def hw(v):
        if dl is None or hg is None:
            return 1.0 if v.co.z > piv.z else 0.0
        return v[dl].get(hg, 0.0) + 0.35 * (v[dl].get(ng, 0.0) if ng is not None else 0.0)
    # delete faces that are mostly head
    kill = [f for f in bm.faces if sum(hw(v) for v in f.verts) / len(f.verts) > 0.35 and f.calc_center_median().z > piv.z - 0.04]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    # leftover high head verts → slim neck disc (match cartoon slim neck)
    for v in list(bm.verts):
        w = hw(v)
        if w > 0.12 and v.co.z > piv.z - 0.05:
            v.co.z = min(v.co.z, piv.z - 0.035)
            v.co.x = piv.x + (v.co.x - piv.x) * 0.32
            v.co.y = piv.y + (v.co.y - piv.y) * 0.32
    # drop any remaining wide "collar shelf" faces above the shoulders
    bm.faces.ensure_lookup_table()
    kill2 = []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.z > piv.z - 0.02:
            kill2.append(f)
            continue
        if c.z > piv.z - 0.06:
            rad = math.hypot(c.x - piv.x, c.y - piv.y)
            if rad > 0.045:
                kill2.append(f)
    if kill2:
        bmesh.ops.delete(bm, geom=kill2, context="FACES")
    bm.verts.ensure_lookup_table()
    edges = [e for e in bm.edges if e.is_boundary and all(v.co.z > piv.z - 0.08 for v in e.verts)]
    if edges:
        try:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        except Exception:
            pass
    # crush any filled neck cap into a slim plug the cartoon neck will cover
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        if v.co.z > piv.z - 0.07:
            rad = math.hypot(v.co.x - piv.x, v.co.y - piv.y)
            if rad > 0.022:
                s = 0.022 / rad
                v.co.x = piv.x + (v.co.x - piv.x) * s
                v.co.y = piv.y + (v.co.y - piv.y) * s
            if v.co.z > piv.z - 0.05:
                v.co.z = piv.z - 0.05
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    print("CARTOON cut MH head, stump at z %.1f cm" % ((piv.z - 0.05) * 100))


def _sphere(bm, c, r, cuts=3, mat=0):
    geo = bmesh.ops.create_icosphere(bm, subdivisions=cuts, radius=r, matrix=Matrix.Translation(c))
    for f in geo["verts"][0].link_faces if False else geo.get("faces", []):
        pass
    # mark material later
    return [v for v in geo["verts"]]


def build_mesh(rig, R, mat_skin, mat_hair):
    """build BoyHead: skull + face + ears + neck + hair helmet/bangs. Returns (ob, eye_centres, info)."""
    hb = Vector(rig.data.bones["head"].head_local)
    # skull centre: above the neck joint; face looks down -Y
    C = hb + Vector((0.0, -0.01 * R / 0.11, 0.095 * R / 0.11))
    # eye line at / slightly below the middle of the head
    eye_z = C.z - 0.01 * R / 0.11
    eye_y = C.y - 0.90 * R
    eye_x = 0.32 * R
    eye_r = 0.20 * R

    bm = bmesh.new()
    # ---- skull (slightly taller dome, softer chin)
    skull_mark = bm.verts.layers.float.new("sk")

    def _skull_verts():
        bm.verts.ensure_lookup_table()
        return [v for v in bm.verts if v.is_valid and v[skull_mark] > 0.5]

    geo = bmesh.ops.create_icosphere(bm, subdivisions=4, radius=R, matrix=Matrix.Translation(C))
    for v in geo["verts"]:
        v[skull_mark] = 1.0
    for v in _skull_verts():
        d = v.co - C
        # flatten the face a little (front -Y) into a soft cheek plane, keep the back round
        front = _ss(0.15 * R, -0.55 * R, d.y)
        # soft round chin: lower front comes forward a touch and narrows
        chin = _ss(0.15 * R, -0.85 * R, d.z) * front
        v.co.x *= 1.0 - 0.18 * chin
        v.co.y -= 0.10 * R * chin
        v.co.z -= 0.04 * R * chin
        # slightly wider cheeks at mid height
        cheek = (1.0 - abs(d.z) / R) * front * _ss(0.05 * R, 0.35 * R, abs(d.x))
        v.co.x *= 1.0 + 0.04 * cheek
        # crown a touch taller
        if d.z > 0:
            v.co.z += 0.04 * R * (d.z / R) ** 2

    # eye sockets: deep cradle so balls sit in (cartoon inset, not bug-eyed)
    for s in (1, -1):
        ec = Vector((s * eye_x, eye_y, eye_z))
        for v in _skull_verts():
            d = v.co - ec
            g = max(0.0, 1.0 - d.length / (eye_r * 1.7))
            g = g * g
            v.co += Vector((0.0, 0.75 * eye_r * g, 0.0))
            v.co.z += 0.1 * eye_r * g * (1.0 if v.co.z > eye_z else -0.5)

    # lid line is painted on face_detail (geometry lids read as blocky spikes at game res)

    # button nose: bump + tiny sphere
    tip = Vector((0.0, C.y - 0.96 * R, eye_z - 0.40 * R))
    for v in _skull_verts():
        d = v.co - tip
        g = max(0.0, 1.0 - d.length / (0.18 * R))
        g = g * g * (3.0 - 2.0 * g)
        v.co += Vector((0.0, -0.08 * R * g, 0.025 * R * g))
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.065 * R,
                               matrix=Matrix.Translation(tip + Vector((0.0, -0.02 * R, 0.0))))

    # ears: small shells on the sides
    for s in (1, -1):
        ec = C + Vector((s * 0.92 * R, 0.05 * R, -0.05 * R))
        ear = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.16 * R,
                                         matrix=Matrix.Translation(ec) @ Matrix.Scale(0.55, 4, (0, 1, 0)) @ Matrix.Scale(0.85, 4, (1, 0, 0)))
        for v in ear["verts"]:
            d = v.co - ec
            if d.x * s < 0:
                v.co.x = ec.x - 0.02 * R * s

    # neck must fill the clothes collar hole (MH neck was ~4–5 cm radius); capped solid plug
    neck_top = C + Vector((0.0, 0.02 * R, -0.75 * R))
    neck_bot = Vector((hb.x, hb.y + 0.01, hb.z - 0.18))
    rings = []
    for p, rr in ((neck_top, 0.32 * R),
                  (neck_top.lerp(neck_bot, 0.25), 0.34 * R),
                  (neck_top.lerp(neck_bot, 0.55), 0.38 * R),
                  (neck_bot, 0.42 * R)):
        ring = [bm.verts.new(p + Vector((math.cos(a) * rr, math.sin(a) * rr * 0.9, 0.0)))
                for a in (2 * math.pi * j / 16 for j in range(16))]
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(16):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % 16], rings[i + 1][(j + 1) % 16], rings[i + 1][j]))
    cap = bm.verts.new(neck_bot)
    for j in range(16):
        bm.faces.new((rings[-1][j], rings[-1][(j + 1) % 16], cap))
    # soft taper of the skull pole into the neck (keep the round chin — only the very bottom)
    for v in _skull_verts():
        d = v.co - C
        if d.z >= -0.70 * R:
            continue
        t = min(1.0, (-0.70 * R - d.z) / (0.30 * R))
        t = t * t * (3.0 - 2.0 * t)
        rad = math.hypot(d.x, d.y)
        want = mix(rad, 0.26 * R, t * 0.85)
        if rad > 1e-8:
            v.co.x = C.x + d.x / rad * want
            v.co.y = C.y + d.y / rad * want * 0.9

    bm.normal_update()
    # ---- hair: separate outer shell (all hair faces) so the hairline is geometry, not a jagged material split
    hair_mark = bm.verts.layers.float.new("hr")
    H = C + Vector((0.0, 0.01 * R, 0.02 * R))
    hel = bmesh.ops.create_icosphere(bm, subdivisions=5, radius=R * 1.06,
                                     matrix=Matrix.Translation(H))
    for v in hel["verts"]:
        v[hair_mark] = 1.0
    bang_cs = [H + Vector((bx * R, -0.72 * R, 0.14 * R + bz * R))
               for bx, bz in ((-0.34, 0.01), (-0.12, -0.02), (0.12, -0.02), (0.34, 0.01))]
    bm.faces.ensure_lookup_table()
    hdel = []
    for f in list(bm.faces):
        if not all(v[hair_mark] > 0.5 for v in f.verts):
            continue
        q = f.calc_center_median() - H
        if q.y < 0.08 * R:
            ang = math.atan2(q.x, max(1e-4, -q.y + 0.02 * R))
            lobe = (0.5 * (1.0 + math.cos(ang * 4.0))) ** 2
            line = 0.08 * R + 0.18 * R * lobe
            if q.z < line:
                hdel.append(f)
    if hdel:
        bmesh.ops.delete(bm, geom=hdel, context="FACES")
    bm.verts.ensure_lookup_table()
    for v in list(bm.verts):
        if not v.is_valid or v[hair_mark] < 0.5:
            continue
        q = v.co - H
        if q.length < 1e-6:
            continue
        n = q.normalized()
        v.co += n * (0.006 * R + 0.018 * R * max(0.0, n.z))
        if q.y < 0.1 * R:
            ang = math.atan2(q.x, max(1e-4, -q.y + 0.02 * R))
            lobe = (0.5 * (1.0 + math.cos(ang * 4.0))) ** 2
            line = 0.08 * R + 0.18 * R * lobe
            if abs(q.z - line) < 0.12 * R:
                v.co.z = mix(v.co.z, H.z + line, 0.55)
                v.co.y = min(v.co.y, H.y - 0.20 * R - 0.08 * R * lobe)
        for bc in bang_cs:
            d = v.co - bc
            g = max(0.0, 1.0 - (d.x * d.x / (0.17 * R) ** 2 + d.y * d.y / (0.14 * R) ** 2 + d.z * d.z / (0.20 * R) ** 2))
            g = g * g * (3.0 - 2.0 * g)
            v.co += Vector((0.0, -0.07 * R * g, -0.055 * R * g))
    bm.edges.ensure_lookup_table()
    rim = [e for e in bm.edges if e.is_boundary and all(v[hair_mark] > 0.5 for v in e.verts)]
    if rim:
        ret = bmesh.ops.extrude_edge_only(bm, edges=rim)
        for v in ret["geom"]:
            if isinstance(v, bmesh.types.BMVert):
                v[hair_mark] = 1.0
                q = v.co - H
                if q.length > 1e-6:
                    v.co += q.normalized() * 0.012 * R
                    v.co += Vector((0.0, 0.008 * R, -0.006 * R))

    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    bm.normal_update()

    # bake hair/skin face flags from the hair_mark layer BEFORE to_mesh (radius heuristics paint the face brown)
    hair_face = [all(v[hair_mark] > 0.5 for v in f.verts) for f in bm.faces]
    me = bpy.data.meshes.new("BoyHead")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat_skin)
    me.materials.append(mat_hair)
    for i, p in enumerate(me.polygons):
        p.material_index = 1 if hair_face[i] else 0
        p.use_smooth = True

    ob = bpy.data.objects.new("BoyHead", me)
    bpy.context.scene.collection.objects.link(ob)
    vg = ob.vertex_groups.new(name="head")
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    for n in ("neck_01", "spine_03", "spine_02"):
        if n not in ob.vertex_groups:
            ob.vertex_groups.new(name=n)
    ob.modifiers.new("Armature", "ARMATURE")
    # eyes sit deeper in the sockets (cartoon, not bug-eyed)
    eyes = {1: Vector((eye_x, C.y - 0.80 * R, eye_z)), -1: Vector((-eye_x, C.y - 0.80 * R, eye_z))}
    info = {"C": C, "R": R, "eye_z": eye_z, "eye_y": eye_y, "eye_r": eye_r, "tip": tip, "hb": hb}
    print("CARTOON head R %.1f cm, eyes at z %.1f cm (mid), eye_r %.1f mm" % (R * 100, eye_z * 100, eye_r * 1000))
    return ob, eyes, info


def mix(a, b, t):
    return a * (1.0 - t) + b * t


def add_shape_keys(ob, info):
    """simple cartoon morphs so boy.gd EXPR keeps working"""
    me = ob.data
    if me.shape_keys is None:
        ob.shape_key_add(name="Basis")
    n = len(me.vertices)
    basis = np.zeros(n * 3)
    me.vertices.foreach_get("co", basis)
    B = basis.reshape(-1, 3).copy()
    C, R = info["C"], info["R"]
    eye_z, eye_y, eye_r = info["eye_z"], info["eye_y"], info["eye_r"]
    tip = info["tip"]

    def add(name, fn):
        k = ob.shape_key_add(name=name, from_mix=False)
        P = B.copy()
        fn(P)
        k.data.foreach_set("co", P.ravel())
        return k

    # blink: upper lids come down over the eyes (pull verts above each eye down and forward)
    def blink(P):
        for s in (1.0, -1.0):
            ec = np.array([s * 0.32 * R, eye_y, eye_z])
            d = P - ec
            r = np.linalg.norm(d, axis=1)
            g = np.clip(1.0 - r / (eye_r * 1.7), 0, 1)
            g = g * g
            up = np.clip((P[:, 2] - eye_z) / (eye_r * 1.2), 0, 1)
            P[:, 2] -= 1.15 * eye_r * g * up
            P[:, 1] -= 0.15 * eye_r * g * up
    add("blink", blink)

    def squint(P):
        blink(P)
        # milder
        P[:] = B + 0.55 * (P - B)
    add("squint", squint)

    # smile: raise mouth corners, puff cheeks slightly — mouth itself is a painted U
    def smile(P):
        mc = np.array([0.0, tip[1] + 0.02 * R, tip[2] - 0.22 * R])
        d = P - mc
        g = np.clip(1.0 - np.linalg.norm(d * np.array([0.7, 1.2, 1.0]), axis=1) / (0.35 * R), 0, 1)
        g = g * g
        # corners up
        P[:, 2] += 0.04 * R * g * np.clip(np.abs(P[:, 0]) / (0.2 * R), 0, 1)
        P[:, 1] -= 0.015 * R * g
        # cheeks
        ck = np.clip(1.0 - np.linalg.norm((P - np.array([0, tip[1], eye_z - 0.15 * R])) * np.array([0.6, 1, 1]), axis=1) / (0.45 * R), 0, 1)
        P[:, 0] += 0.02 * R * ck * np.sign(P[:, 0] + 1e-9) * g
    add("smile", smile)

    def open_m(P):
        mc = np.array([0.0, tip[1] + 0.02 * R, tip[2] - 0.22 * R])
        d = P - mc
        g = np.clip(1.0 - np.linalg.norm(d * np.array([1.0, 1.4, 0.8]), axis=1) / (0.22 * R), 0, 1)
        g = g * g
        P[:, 2] -= 0.06 * R * g * np.clip((mc[2] - P[:, 2]) / (0.08 * R) + 0.5, 0, 1)
        P[:, 2] += 0.04 * R * g * np.clip((P[:, 2] - mc[2]) / (0.08 * R) + 0.5, 0, 1)
        P[:, 1] += 0.02 * R * g
    add("open", open_m)

    def frown(P):
        mc = np.array([0.0, tip[1] + 0.02 * R, tip[2] - 0.22 * R])
        g = np.clip(1.0 - np.linalg.norm((P - mc) * np.array([0.7, 1.2, 1.0]), axis=1) / (0.32 * R), 0, 1) ** 2
        P[:, 2] -= 0.03 * R * g * np.clip(np.abs(P[:, 0]) / (0.18 * R), 0, 1)
    add("frown", frown)

    def press(P):
        open_m(P)
        P[:] = B + 0.35 * (P - B)
        P[:, 2] += 0.01 * R  # lips together-ish
    add("press", press)

    def brow_up(P):
        for s in (1.0, -1.0):
            bc = np.array([s * 0.28 * R, eye_y + 0.05 * R, eye_z + 0.28 * R])
            g = np.clip(1.0 - np.linalg.norm(P - bc, axis=1) / (0.22 * R), 0, 1) ** 2
            P[:, 2] += 0.025 * R * g
    add("brow_up", brow_up)

    def brow_in(P):
        for s in (1.0, -1.0):
            bc = np.array([s * 0.18 * R, eye_y + 0.05 * R, eye_z + 0.26 * R])
            g = np.clip(1.0 - np.linalg.norm(P - bc, axis=1) / (0.18 * R), 0, 1) ** 2
            P[:, 0] -= 0.02 * R * g * s
            P[:, 2] += 0.01 * R * g
    add("brow_in", brow_in)

    def brow_down(P):
        for s in (1.0, -1.0):
            bc = np.array([s * 0.28 * R, eye_y + 0.05 * R, eye_z + 0.28 * R])
            g = np.clip(1.0 - np.linalg.norm(P - bc, axis=1) / (0.22 * R), 0, 1) ** 2
            P[:, 2] -= 0.02 * R * g
    add("brow_down", brow_down)
    print("CARTOON shape keys", [k.name for k in me.shape_keys.key_blocks[1:]])


def build_eyes(rig, eyes, eye_r, mat):
    """two UV-sphere eyeballs, bone-parented to head. Iris/pupil/sclera baked into vertex COLOR
    (survives glTF axis flip); shader adds catchlights on top."""
    bm = bmesh.new()
    centres = {}
    for s, c in eyes.items():
        bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=18, radius=eye_r * 0.92,
                                  matrix=Matrix.Translation(c))
        centres[s] = c
    me = bpy.data.meshes.new("Eyes")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    uv = me.uv_layers.new(name="UVMap")
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    iris_r, pupil_r = 0.90, 0.30
    sclera = (1.0, 0.99, 0.96, 1.0)
    for p in me.polygons:
        for li, vi in zip(p.loop_indices, p.vertices):
            co = me.vertices[vi].co
            s = 1 if co.x >= 0 else -1
            c = centres[s]
            loc = co - c
            # Blender face front is -Y
            front = max(0.0, -loc.y / (eye_r * 0.92))
            rr = math.hypot(loc.x, loc.z) / (eye_r * 0.92)
            lx = loc.x / (eye_r * 1.1)
            lz = loc.z / (eye_r * 1.1)
            if s > 0:
                uv.data[li].uv = (0.707 + lx * 0.22, 0.297 + lz * 0.22)
            else:
                uv.data[li].uv = (0.293 + lx * 0.22, 0.707 + lz * 0.22)
            if front < 0.12:
                rgb = sclera
            elif rr < pupil_r * 0.95:
                rgb = (0.05, 0.035, 0.03, 1.0)
            elif rr < iris_r * 1.05:

                t = (rr - pupil_r) / max(iris_r - pupil_r, 1e-4)
                # hazel: warm in → darker limbal out
                r = 0.92 - 0.50 * t
                g = 0.58 - 0.34 * t
                b = 0.22 - 0.14 * t
                if t > 0.72:
                    k = (t - 0.72) / 0.28
                    r, g, b = r * (1 - 0.5 * k) + 0.14 * k, g * (1 - 0.5 * k) + 0.08 * k, b * (1 - 0.5 * k) + 0.04 * k
                rgb = (r, g, b, 1.0)
            else:
                # thin warm-white sclera ring
                rgb = sclera
            # soften onto back of ball
            if front < 0.45:
                k = front / 0.45
                rgb = (rgb[0] * k + sclera[0] * (1 - k), rgb[1] * k + sclera[1] * (1 - k),
                       rgb[2] * k + sclera[2] * (1 - k), 1.0)
            col.data[vi].color = rgb
    ob = bpy.data.objects.new("Eyes", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def paint_face(ob, info, path):
    """cartoon face_detail.png in head front projection (UV2): thick lid line, U smile, saturated blush"""
    me = ob.data
    C, R = info["C"], info["R"]
    eye_z, eye_y, eye_r = info["eye_z"], info["eye_y"], info["eye_r"]
    tip = info["tip"]
    hb = info["hb"]
    N = 512
    # UV2: front projection metres from head joint (same convention as face.RECT)
    if "Face" not in me.uv_layers and len(me.uv_layers) < 2:
        me.uv_layers.new(name="UVMap")
    while len(me.uv_layers) < 2:
        me.uv_layers.new()
    me.uv_layers[0].name = "UVMap"
    me.uv_layers[1].name = "Face"
    fl = me.uv_layers["Face"]
    for li, loop in enumerate(me.loops):
        co = me.vertices[loop.vertex_index].co
        fl.data[li].uv = (co.x, co.z - hb.z)

    # paint in metres from the head joint (shader face_rect)
    x0, y0, w, h = -0.12, -0.14, 0.24, 0.30
    gx = np.linspace(x0, x0 + w, N)
    gy = np.linspace(y0, y0 + h, N)
    PX, PY = np.meshgrid(gx, gy)
    Rch = np.zeros((N, N))
    Gch = np.zeros((N, N))
    Bch = np.zeros((N, N))
    Ach = np.zeros((N, N))

    def ss(a, b, x):
        t = np.clip((x - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)

    def gauss(cx, cy, sx, sy):
        return np.exp(-((PX - cx) / sx) ** 2 - ((PY - cy) / sy) ** 2)

    # eyes in UV2 (x, z - head_joint.z)
    for s in (1, -1):
        cx = s * eye_x if "eye_x" in dir() else s * 0.32 * R
        cx = s * 0.32 * R
        cy = eye_z - hb.z
        # thick curved upper lid line (darken + brow channels so it reads at game camera)
        xs = np.linspace(cx - eye_r * 1.15, cx + eye_r * 1.15, 48)
        ys = cy + eye_r * 0.62 * np.sqrt(np.clip(1 - ((xs - cx) / (eye_r * 1.15)) ** 2, 0, 1))
        for i in range(len(xs) - 1):
            x0s, y0s = xs[i], ys[i]
            x1s, y1s = xs[i + 1], ys[i + 1]
            vx, vy = x1s - x0s, y1s - y0s
            L2 = vx * vx + vy * vy + 1e-12
            t = np.clip(((PX - x0s) * vx + (PY - y0s) * vy) / L2, 0, 1)
            dist = np.hypot(PX - (x0s + t * vx), PY - (y0s + t * vy))
            lid = 1.0 - ss(0.0012, 0.0038, dist)
            Bch = np.maximum(Bch, lid * 1.0)
            Rch = np.maximum(Rch, lid * 0.85)
        # soft brow
        by = cy + eye_r * 1.4
        Rch = np.maximum(Rch, gauss(cx, by, eye_r * 0.95, eye_r * 0.24) * 0.6)
        # saturated peach-pink blush
        Ach = np.maximum(Ach, gauss(cx + s * 0.018 * R, cy - 0.40 * R, 0.036, 0.024) * 1.0)

    # closed U smile
    mx, my = 0.0, tip[2] - hb.z - 0.08 * R
    mw = 0.14 * R
    xs = np.linspace(mx - mw, mx + mw, 50)
    # U: corners up
    ys = my + 0.045 * R * ((xs - mx) / mw) ** 2 - 0.01 * R
    for i in range(len(xs) - 1):
        x0s, y0s = xs[i], ys[i]
        x1s, y1s = xs[i + 1], ys[i + 1]
        vx, vy = x1s - x0s, y1s - y0s
        L2 = vx * vx + vy * vy + 1e-12
        t = np.clip(((PX - x0s) * vx + (PY - y0s) * vy) / L2, 0, 1)
        dist = np.hypot(PX - (x0s + t * vx), PY - (y0s + t * vy))
        # lips: soft pink band around the U line
        Gch = np.maximum(Gch, (1.0 - ss(0.0006, 0.0028, dist)) * 0.85)
        Bch = np.maximum(Bch, (1.0 - ss(0.0003, 0.0010, dist)) * 0.35)
    # nose tip warmth
    Ach = np.maximum(Ach, gauss(0.0, tip[2] - hb.z, 0.008, 0.007) * 0.35)

    img = np.stack([Rch, Gch, Bch, Ach], axis=-1).astype(np.float32)
    im = bpy.data.images.new("face_detail", N, N, alpha=True, float_buffer=False)
    im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(np.clip(img, 0.0, 1.0).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    # store rect for meta
    ob["face_rect"] = [float(x0), float(y0), float(w), float(h)]
    print("CARTOON FACE MAP", path, "rect", list(ob["face_rect"]))
    return list(ob["face_rect"])


def _hair_data(ob, info):
    """UV2 sway + cb under-crown for hair faces on BoyHead"""
    me = ob.data
    while len(me.uv_layers) < 2:
        me.uv_layers.new()
    me.uv_layers[0].name = "UVMap"
    me.uv_layers[1].name = "Face"
    fl = me.uv_layers["Face"]
    hair_mi = [i for i, m in enumerate(me.materials) if m and m.name == "hair"]
    C, R = info["C"], info["R"]
    if "cb" not in me.attributes:
        me.attributes.new("cb", "FLOAT", "POINT")
    cb = me.attributes["cb"]
    for i, v in enumerate(me.vertices):
        # under hat crown roughly: upper hemisphere
        q = v.co - C
        cb.data[i].value = 1.0 if q.z > 0.05 * R and q.y > -0.35 * R else 0.0
    for p in me.polygons:
        is_hair = p.material_index in hair_mi
        for li, vi in zip(p.loop_indices, p.vertices):
            if is_hair:
                # root-tip-ish from height; sway stronger on bangs (front)
                q = me.vertices[vi].co - C
                tip = max(0.0, 0.5 - q.z / R)
                sway = tip * (0.3 + 0.7 * _ss(0.1 * R, -0.4 * R, q.y))
                # Blender V=1 → glTF flips to 0 → hair.gdshader mass = step(0.5, 1-UV2.y) ≈ 1
                fl.data[li].uv = (sway, 1.0)
            # skin Face UV set in paint_face


def bind_head(ob, rig):
    ob.parent = rig
    mod = ob.modifiers.get("Armature") or ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig


def install(rig, body, mat_skin, mat_eye, mat_hair, face_path, head_scale=1.38):
    """cut MH head, build cartoon BoyHead + Eyes, paint face. Returns (head, eyes, info)."""
    # estimate R from the current (scaled) head if still present, else from head bone
    hb = Vector(rig.data.bones["head"].head_local)
    # body still has MH head before cut — measure
    head_vs = [v.co for v in body.data.vertices if _weight(body, v, "head") > 0.5 and v.co.z > hb.z]
    if head_vs:
        top = max(v.z for v in head_vs)
        # half-width
        hw = max(abs(v.x) for v in head_vs)
        R0 = max(0.5 * (top - hb.z), hw) * 0.95
    else:
        R0 = 0.10
    R = R0 * CHIBI
    if "Eyes" in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects["Eyes"], do_unlink=True)
    if "BoyHead" in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects["BoyHead"], do_unlink=True)
    cut_body_head(rig, body)
    head, eyes_c, info = build_mesh(rig, R, mat_skin, mat_hair)
    bind_head(head, rig)
    add_shape_keys(head, info)
    _hair_data(head, info)
    rect = paint_face(head, info, face_path)
    info["face_rect"] = rect
    eyes = build_eyes(rig, eyes_c, info["eye_r"], mat_eye)
    # bone-parent eyes like before
    eyes.parent = rig
    eyes.parent_type = "BONE"
    eyes.parent_bone = "head"
    b = rig.data.bones["head"]
    eyes.matrix_parent_inverse = (rig.matrix_world @ b.matrix_local @ Matrix.Translation((0, b.length, 0))).inverted()
    # stash eye UV centres for meta (x, z-hb.z)
    body["eyes_uv"] = [(eyes_c[1].x, eyes_c[1].z - hb.z), (eyes_c[-1].x, eyes_c[-1].z - hb.z)]
    body["cartoon_info"] = info
    # head top for hat
    info["head_top"] = max(v.co.z for v in head.data.vertices)
    return head, eyes, info
