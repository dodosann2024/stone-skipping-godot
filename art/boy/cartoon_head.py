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
    """remove MakeHuman head AND old neck; bury a tiny stump deep in the chest so nothing
    pokes through the cartoon neck / collar."""
    hb = rig.data.bones["head"]
    piv = Vector(hb.head_local)
    # bury stump well below the shoulder line (spine_03 / clavicle height)
    bury_z = piv.z - 0.12
    hg = body.vertex_groups["head"].index if "head" in body.vertex_groups else None
    ng = body.vertex_groups["neck_01"].index if "neck_01" in body.vertex_groups else None
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    dl = bm.verts.layers.deform.active
    def hw(v):
        if dl is None or hg is None:
            return 1.0 if v.co.z > piv.z - 0.08 else 0.0
        return v[dl].get(hg, 0.0) + 0.85 * (v[dl].get(ng, 0.0) if ng is not None else 0.0)
    # delete head + old neck faces (anything mostly head/neck above the chest)
    kill = [f for f in bm.faces
            if sum(hw(v) for v in f.verts) / len(f.verts) > 0.25
            and f.calc_center_median().z > bury_z + 0.02]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    # also delete any leftover shelf around the collarbone (wide faces near the neck axis)
    bm.faces.ensure_lookup_table()
    kill2 = []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.z > bury_z + 0.04 and math.hypot(c.x - piv.x, c.y - piv.y) < 0.10:
            kill2.append(f)
        elif c.z > piv.z - 0.08:
            kill2.append(f)
    if kill2:
        bmesh.ops.delete(bm, geom=kill2, context="FACES")
    # crush remaining high verts into a tiny buried plug (hidden inside the vest)
    bm.verts.ensure_lookup_table()
    for v in list(bm.verts):
        if v.co.z > bury_z:
            rad = math.hypot(v.co.x - piv.x, v.co.y - piv.y)
            v.co.z = bury_z
            if rad > 0.015:
                s = 0.015 / rad
                v.co.x = piv.x + (v.co.x - piv.x) * s
                v.co.y = piv.y + (v.co.y - piv.y) * s
    bm.verts.ensure_lookup_table()
    edges = [e for e in bm.edges if e.is_boundary and all(v.co.z > bury_z - 0.03 for v in e.verts)]
    if edges:
        try:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        except Exception:
            pass
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        if v.co.z > bury_z - 0.01:
            rad = math.hypot(v.co.x - piv.x, v.co.y - piv.y)
            if rad > 0.012:
                s = 0.012 / rad
                v.co.x = piv.x + (v.co.x - piv.x) * s
                v.co.y = piv.y + (v.co.y - piv.y) * s
            v.co.z = min(v.co.z, bury_z)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    print("CARTOON cut MH head+neck, stump buried at z %.1f cm" % (bury_z * 100))


def clean_collar(rig, objs):
    """delete the crumpled neck-hole crater on tank/vest/body, then push remaining
    neckline verts down/out so the short cartoon neck covers the opening cleanly."""
    piv = Vector(rig.data.bones["head"].head_local)
    # stump was buried near piv.z-0.12; clothes inherit that crater — clear a wide cone
    cut_z = piv.z - 0.02
    for ob in objs:
        if ob is None or ob.type != "MESH":
            continue
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        kill = []
        for f in bm.faces:
            c = f.calc_center_median()
            rad = math.hypot(c.x - piv.x, c.y - piv.y)
            # open a clean circular neck hole; drop anything that would poke past the flare
            if c.z > piv.z - 0.14 and rad < 0.095:
                kill.append(f)
            elif c.z > piv.z - 0.10 and rad < 0.12:
                kill.append(f)
        if kill:
            bmesh.ops.delete(bm, geom=kill, context="FACES")
        bm.verts.ensure_lookup_table()
        n = 0
        for v in bm.verts:
            if v.co.z < piv.z - 0.16:
                continue
            rad = math.hypot(v.co.x - piv.x, v.co.y - piv.y)
            if rad > 0.14:
                continue
            # push collar down and slightly out under the cartoon neck flare
            v.co.z = min(v.co.z, cut_z - 0.055 - max(0.0, 0.08 - rad) * 0.5)
            if rad < 0.10 and rad > 1e-6:
                s = min(0.11 / rad, 1.55)
                v.co.x = piv.x + (v.co.x - piv.x) * s
                v.co.y = piv.y + (v.co.y - piv.y) * s
            n += 1
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()
        print("CARTOON clean_collar", ob.name, "killed", len(kill) if kill else 0, "verts", n)


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

    # short, thick child neck that blends into the shoulders (Concept A — not a stick).
    neck_top = C + Vector((0.0, 0.02 * R, -0.62 * R))
    neck_bot = Vector((hb.x, hb.y + 0.02, hb.z - 0.08))
    rings = []
    for p, rr in ((neck_top, 0.50 * R),
                  (neck_top.lerp(neck_bot, 0.35), 0.56 * R),
                  (neck_top.lerp(neck_bot, 0.70), 0.66 * R),
                  (neck_bot, 0.78 * R)):  # wide flare into shoulders / vest
        ring = [bm.verts.new(p + Vector((math.cos(a) * rr, math.sin(a) * rr * 0.90, 0.0)))
                for a in (2 * math.pi * j / 20 for j in range(20))]
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(20):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % 20], rings[i + 1][(j + 1) % 20], rings[i + 1][j]))
    # open bottom (no end-cap) so it sits over the vest like a soft turtleneck flare
    # soft taper of the skull pole into the thick short neck (keeps round chin, no step)
    for v in _skull_verts():
        d = v.co - C
        if d.z >= -0.50 * R:
            continue
        t = min(1.0, (-0.50 * R - d.z) / (0.35 * R))
        t = t * t * (3.0 - 2.0 * t)
        rad = math.hypot(d.x, d.y)
        want = mix(rad, 0.46 * R, t * 0.95)
        if rad > 1e-8:
            v.co.x = C.x + d.x / rad * want
            v.co.y = C.y + d.y / rad * want * 0.90
            # pull the chin/neck join forward a touch so the step disappears in side view
            v.co.y -= 0.02 * R * t
            v.co.z = mix(v.co.z, neck_top.z + 0.02 * R, t * 0.35)

    bm.normal_update()
    # ---- hair: Concept A — thin skull-hug shell (~1.5 cm), chunky bangs, short side/back tufts.
    # Must sit INSIDE the hat; silhouette never exceeds hat brim.
    hair_mark = bm.verts.layers.float.new("hr")
    H = C + Vector((0.0, 0.01 * R, 0.0))
    HAIR_T = 0.012  # ~1.2 cm skull-hug shell (Concept A: 1–2 cm)
    hel = bmesh.ops.create_icosphere(
        bm, subdivisions=4, radius=R + HAIR_T,
        matrix=Matrix.Translation(H))
    for v in hel["verts"]:
        v[hair_mark] = 1.0
    # open a large face window so the shell is a thin cap+nape, not a brown dome over the face
    bm.faces.ensure_lookup_table()
    hdel = []
    for f in list(bm.faces):
        if not all(v[hair_mark] > 0.5 for v in f.verts):
            continue
        q = f.calc_center_median() - H
        n = q.normalized() if q.length > 1e-8 else Vector((0, -1, 0))
        # delete most of the forward hemisphere below mid-forehead
        if n.y < -0.12 and n.z < 0.42:
            hdel.append(f)
        # temples open so bangs read as clumps, not a solid helmet front
        elif n.y < -0.28 and abs(n.x) < 0.62 and n.z < 0.58:
            hdel.append(f)
    if hdel:
        bmesh.ops.delete(bm, geom=hdel, context="FACES")
    # clamp every hair vert to a thin shell (~1.0–1.4 cm) — never exceed hat brim
    MAX_HAIR = R + 0.014
    bm.verts.ensure_lookup_table()
    for v in list(bm.verts):
        if not v.is_valid or v[hair_mark] < 0.5:
            continue
        q = v.co - H
        if q.length < 1e-6:
            continue
        n = q.normalized()
        want = R + 0.010 + 0.003 * max(0.0, n.z)
        v.co = H + n * min(want, MAX_HAIR)
        # nape / side hairline a bit lower (short tufts hugging skull)
        if n.y > -0.20 and n.z < 0.20:
            v.co.z -= 0.040 * R * _ss(-0.15, 0.55, n.y)
    # chunky rounded bang clumps over the forehead (Concept A) — under the hat brim
    bang_cs = [
        H + Vector((bx * R, -0.90 * R, 0.08 * R + bz * R))
        for bx, bz in ((-0.34, 0.05), (-0.12, 0.0), (0.12, 0.0), (0.34, 0.05))
    ]
    for bc in bang_cs:
        bang = bmesh.ops.create_icosphere(
            bm, subdivisions=2, radius=0.055 * R,
            matrix=Matrix.Translation(bc) @ Matrix.Scale(1.35, 4, (1, 0, 0))
            @ Matrix.Scale(0.55, 4, (0, 1, 0)) @ Matrix.Scale(1.25, 4, (0, 0, 1)))
        for v in bang["verts"]:
            v[hair_mark] = 1.0
            # keep bangs close to the forehead, never a giant outer sphere
            q = v.co - H
            if q.length > MAX_HAIR + 0.010:
                v.co = H + q.normalized() * (MAX_HAIR + 0.008)
            # hang bang tips slightly down over the forehead
            v.co.z -= 0.018 * R
            v.co.y -= 0.012 * R
    # soft rim on the open hairline
    bm.edges.ensure_lookup_table()
    rim = [e for e in bm.edges if e.is_boundary and all(v[hair_mark] > 0.5 for v in e.verts)]
    if rim:
        ret = bmesh.ops.extrude_edge_only(bm, edges=rim)
        for v in ret["geom"]:
            if isinstance(v, bmesh.types.BMVert):
                v[hair_mark] = 1.0
                q = v.co - H
                if q.length > 1e-6:
                    v.co += q.normalized() * 0.006
                    v.co += Vector((0.0, 0.004, -0.008))
                    q2 = v.co - H
                    if q2.length > MAX_HAIR + 0.01:
                        v.co = H + q2.normalized() * (MAX_HAIR + 0.008)
    # light smooth on hair boundary
    bm.verts.ensure_lookup_table()
    for _ in range(2):
        moves = []
        for v in bm.verts:
            if not v.is_valid or v[hair_mark] < 0.5 or not v.is_boundary:
                continue
            nbrs = [e.other_vert(v).co for e in v.link_edges if e.other_vert(v) is not None]
            if nbrs:
                avg = sum(nbrs, Vector()) / len(nbrs)
                moves.append((v, v.co.lerp(avg, 0.35)))
        for v, co in moves:
            v.co = co

    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
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
    (survives glTF axis flip); shader adds catchlights on top.

    Sphere is rotated so a pole faces -Y (front): dense latitude rings keep the pupil round
    instead of a square hole from sparse Z-pole topology on the face disc.
    """
    bm = bmesh.new()
    centres = {}
    # -90° about X: Blender UV-sphere +Z pole → -Y (face forward)
    face_rot = Matrix.Rotation(math.radians(-90.0), 4, "X")
    for s, c in eyes.items():
        bmesh.ops.create_uvsphere(
            bm, u_segments=48, v_segments=24, radius=eye_r * 0.92,
            matrix=Matrix.Translation(c) @ face_rot)
        centres[s] = c
    me = bpy.data.meshes.new("Eyes")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    uv = me.uv_layers.new(name="UVMap")
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    # iris ~65% of eye height so a clear white sclera ring remains; round dark pupil
    iris_r, pupil_r = 0.66, 0.24
    sclera = (1.0, 0.995, 0.97, 1.0)
    # bake one big + one small round catchlight into COLOR so they stay circular at low res
    for p in me.polygons:
        for li, vi in zip(p.loop_indices, p.vertices):
            co = me.vertices[vi].co
            s = 1 if co.x >= 0 else -1
            c = centres[s]
            loc = co - c
            # face front is -Y; disc in XZ
            front = max(0.0, -loc.y / (eye_r * 0.92))
            rr = math.hypot(loc.x, loc.z) / (eye_r * 0.92)
            lx = loc.x / (eye_r * 1.1)
            lz = loc.z / (eye_r * 1.1)
            if s > 0:
                uv.data[li].uv = (0.707 + lx * 0.22, 0.297 + lz * 0.22)
            else:
                uv.data[li].uv = (0.293 + lx * 0.22, 0.707 + lz * 0.22)
            if front < 0.05:
                rgb = sclera
            elif rr < pupil_r:
                # soft edge into iris so the pupil never reads as a square texel hole
                t = rr / max(pupil_r, 1e-4)
                edge = _ss(0.82, 1.0, t)
                pr, pg, pb = 0.04, 0.025, 0.02
                ir, ig, ib = 0.28, 0.16, 0.10  # dark brown (Concept A)
                rgb = (pr * (1 - edge) + ir * edge, pg * (1 - edge) + ig * edge,
                       pb * (1 - edge) + ib * edge, 1.0)
            elif rr < iris_r:
                t = (rr - pupil_r) / max(iris_r - pupil_r, 1e-4)
                # dark brown iris with soft limbus → white sclera ring
                r = 0.32 - 0.12 * t
                g = 0.18 - 0.08 * t
                b = 0.11 - 0.04 * t
                if t > 0.78:
                    k = (t - 0.78) / 0.22
                    r, g, b = r * (1 - 0.55 * k) + 0.10 * k, g * (1 - 0.55 * k) + 0.06 * k, b * (1 - 0.55 * k) + 0.04 * k
                    if t > 0.92:
                        k2 = (t - 0.92) / 0.08
                        r = r * (1 - k2) + sclera[0] * k2
                        g = g * (1 - k2) + sclera[1] * k2
                        b = b * (1 - k2) + sclera[2] * k2
                rgb = (r, g, b, 1.0)
            else:
                rgb = sclera
            # only fade toward sclera on the back/side of the ball — never wash out the front iris
            if front < 0.15 and rr > iris_r * 0.5:
                k = front / 0.15
                rgb = (rgb[0] * k + sclera[0] * (1 - k), rgb[1] * k + sclera[1] * (1 - k),
                       rgb[2] * k + sclera[2] * (1 - k), 1.0)
            # baked catchlights (upper-left big, lower-right small) — stay round at game res
            if front > 0.55:
                cl1 = math.hypot(loc.x / (eye_r * 0.92) + 0.18 * s, loc.z / (eye_r * 0.92) - 0.22)
                cl2 = math.hypot(loc.x / (eye_r * 0.92) - 0.12 * s, loc.z / (eye_r * 0.92) + 0.10)
                if cl1 < 0.11:
                    w = 1.0 - _ss(0.06, 0.11, cl1)
                    rgb = (mix(rgb[0], 1.0, w), mix(rgb[1], 1.0, w), mix(rgb[2], 0.98, w), 1.0)
                if cl2 < 0.055:
                    w = 1.0 - _ss(0.025, 0.055, cl2)
                    rgb = (mix(rgb[0], 1.0, w * 0.9), mix(rgb[1], 1.0, w * 0.9), mix(rgb[2], 0.98, w * 0.9), 1.0)
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
        # thinner upper lid line (separate from the brow)
        xs = np.linspace(cx - eye_r * 1.05, cx + eye_r * 1.05, 40)
        ys = cy + eye_r * 0.55 * np.sqrt(np.clip(1 - ((xs - cx) / (eye_r * 1.05)) ** 2, 0, 1))
        for i in range(len(xs) - 1):
            x0s, y0s = xs[i], ys[i]
            x1s, y1s = xs[i + 1], ys[i + 1]
            vx, vy = x1s - x0s, y1s - y0s
            L2 = vx * vx + vy * vy + 1e-12
            t = np.clip(((PX - x0s) * vx + (PY - y0s) * vy) / L2, 0, 1)
            dist = np.hypot(PX - (x0s + t * vx), PY - (y0s + t * vy))
            lid = 1.0 - ss(0.0004, 0.0012, dist)
            Bch = np.maximum(Bch, lid * 0.75)
        # thinner arches placed higher above the lid
        by = cy + eye_r * 1.85
        xs = np.linspace(cx - eye_r * 0.80, cx + eye_r * 0.80, 32)
        ys = by + eye_r * 0.10 * np.sqrt(np.clip(1 - ((xs - cx) / (eye_r * 0.80)) ** 2, 0, 1))
        for i in range(len(xs) - 1):
            x0s, y0s = xs[i], ys[i]
            x1s, y1s = xs[i + 1], ys[i + 1]
            vx, vy = x1s - x0s, y1s - y0s
            L2 = vx * vx + vy * vy + 1e-12
            t = np.clip(((PX - x0s) * vx + (PY - y0s) * vy) / L2, 0, 1)
            dist = np.hypot(PX - (x0s + t * vx), PY - (y0s + t * vy))
            Rch = np.maximum(Rch, (1.0 - ss(0.00035, 0.0011, dist)) * 0.55)
        # soft light-pink blush (very gentle — not red patches)
        Ach = np.maximum(Ach, gauss(cx + s * 0.015 * R, cy - 0.36 * R, 0.034, 0.022) * 0.22)

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


def install(rig, body, mat_skin, mat_eye, mat_hair, face_path, head_scale=1.38, head_r=None):
    """build stylized BoyHead + Eyes, paint face. Returns (head, eyes, info).

    If head_r is given (Concept A full-body path), use it directly and only trim any
    leftover body verts above the neck. Otherwise fall back to measuring / cutting an MH head.
    """
    hb = Vector(rig.data.bones["head"].head_local)
    if head_r is not None:
        R = float(head_r)
    else:
        head_vs = [v.co for v in body.data.vertices if _weight(body, v, "head") > 0.5 and v.co.z > hb.z]
        if head_vs:
            top = max(v.z for v in head_vs)
            hw = max(abs(v.x) for v in head_vs)
            R0 = max(0.5 * (top - hb.z), hw) * 0.95
        else:
            R0 = 0.10
        R = R0 * CHIBI * head_scale / 1.38
    if "Eyes" in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects["Eyes"], do_unlink=True)
    if "BoyHead" in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects["BoyHead"], do_unlink=True)
    if head_r is None:
        # MH path: cut the realistic head/neck off the body
        cut_body_head(rig, body)
    else:
        # Concept A path: body is already a soft stump; just trim anything above the neck joint
        bm = bmesh.new()
        bm.from_mesh(body.data)
        kill = [f for f in bm.faces if f.calc_center_median().z > hb.z + 0.01]
        if kill:
            bmesh.ops.delete(bm, geom=kill, context="FACES")
        bm.to_mesh(body.data)
        bm.free()
        body.data.update()
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
