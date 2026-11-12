"""v22 Concept A — full soft stylized body (Nintendo / Animal-Crossing-like).

Builds a ~4-heads-tall soft body mesh weighted to the game_engine skeleton after
retargeting bone lengths to chibi proportions. Replaces the MakeHuman body mesh
entirely so head/body/limbs share one style.
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

# target proportions (Blender metres, soles near GROUND)
# ~4 heads tall at a playable height (island seats / hammock / gait probes assume ~1.1 m)
HEAD_R = 0.140          # big round head radius
TOTAL_H = 1.12          # head ~0.28 tall → ~4 heads
GROUND = -0.012


def _ss(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _mix(a, b, t):
    return a * (1.0 - t) + b * t


def retarget_chibi(rig):
    """shrink the game_engine skeleton to ~4-heads soft-child proportions while
    keeping bone names / hierarchy / orientations for boy.gd + posekit."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones

    # desired joint heights (z) and half-widths
    # head centre near neck + HEAD_R*0.85; crown ≈ neck + 1.9*HEAD_R
    neck_z = TOTAL_H - 2.05 * HEAD_R          # ~0.77
    head_z = neck_z + 0.02
    head_tail_z = neck_z + 1.85 * HEAD_R
    sh_z = neck_z - 0.04
    chest_z = sh_z - 0.06
    mid_z = chest_z - 0.07
    pel_z = 0.44
    hip_x = 0.078
    sh_x = 0.108
    knee_z = 0.215
    ankle_z = 0.045
    ball_y = -0.065

    def set_bone(name, head, tail, parent=None):
        b = eb[name]
        b.head = Vector(head)
        b.tail = Vector(tail)
        if parent:
            b.parent = eb[parent]

    # spine
    set_bone("pelvis", (0, 0.01, pel_z), (0, 0.01, mid_z))
    set_bone("spine_01", (0, 0.01, mid_z), (0, 0.005, chest_z), "pelvis")
    set_bone("spine_02", (0, 0.005, chest_z), (0, 0.0, sh_z - 0.02), "spine_01")
    set_bone("spine_03", (0, 0.0, sh_z - 0.02), (0, 0.0, sh_z), "spine_02")
    set_bone("neck_01", (0, 0.0, sh_z), (0, -0.005, neck_z), "spine_03")
    set_bone("head", (0, -0.005, neck_z), (0, -0.02, head_tail_z), "neck_01")

    # legs
    for s, sx in (("l", 1.0), ("r", -1.0)):
        set_bone("thigh_" + s, (sx * hip_x, 0.01, pel_z - 0.01),
                 (sx * hip_x * 0.95, 0.01, knee_z), "pelvis")
        set_bone("calf_" + s, (sx * hip_x * 0.95, 0.01, knee_z),
                 (sx * hip_x * 0.9, 0.02, ankle_z), "thigh_" + s)
        set_bone("foot_" + s, (sx * hip_x * 0.9, 0.02, ankle_z),
                 (sx * hip_x * 0.9, ball_y, 0.01), "calf_" + s)
        set_bone("ball_" + s, (sx * hip_x * 0.9, ball_y, 0.01),
                 (sx * hip_x * 0.9, ball_y - 0.03, GROUND + 0.005), "foot_" + s)

    # arms — short soft limbs
    for s, sx in (("l", 1.0), ("r", -1.0)):
        set_bone("clavicle_" + s, (sx * 0.03, 0.0, sh_z),
                 (sx * sh_x * 0.78, 0.0, sh_z - 0.005), "spine_03")
        # a touch longer / more outboard arms so throw/cheer clear the round torso
        set_bone("upperarm_" + s, (sx * sh_x * 0.78, 0.0, sh_z - 0.005),
                 (sx * (sh_x + 0.11), 0.02, sh_z - 0.155), "clavicle_" + s)
        set_bone("lowerarm_" + s, (sx * (sh_x + 0.11), 0.02, sh_z - 0.155),
                 (sx * (sh_x + 0.135), 0.03, sh_z - 0.29), "upperarm_" + s)
        set_bone("hand_" + s, (sx * (sh_x + 0.135), 0.03, sh_z - 0.29),
                 (sx * (sh_x + 0.145), 0.04, sh_z - 0.35), "lowerarm_" + s)
        # simple finger stubs (kept for hat grip / boy.gd)
        hand = eb["hand_" + s]
        hx, hy, hz = hand.tail
        for i, fname in enumerate(("thumb", "index", "middle", "ring", "pinky")):
            fx = sx * (0.012 + 0.008 * i)
            for k in (1, 2, 3):
                name = "%s_0%d_%s" % (fname, k, s)
                if name not in eb:
                    continue
                z0 = hz - 0.012 * (k - 1)
                z1 = hz - 0.012 * k
                y0 = hy + 0.008 * k
                set_bone(name, (hx + fx, y0, z0), (hx + fx, y0 + 0.008, z1),
                         "hand_" + s if k == 1 else "%s_0%d_%s" % (fname, k - 1, s))
        for dname in ("deltoid_" + s,):
            if dname in eb:
                set_bone(dname, (sx * sh_x * 0.75, 0.0, sh_z - 0.01),
                         (sx * (sh_x + 0.04), -0.02, sh_z - 0.06), "clavicle_" + s)

    bpy.ops.object.mode_set(mode="OBJECT")
    print("STYLIZED retarget chibi: neck_z %.1f cm, head_tail %.1f cm, pel_z %.1f cm"
          % (neck_z * 100, head_tail_z * 100, pel_z * 100))
    return {"HEAD_R": HEAD_R, "TOTAL_H": TOTAL_H, "neck_z": neck_z, "pel_z": pel_z}


def _add_capsule(bm, a, b, r0, r1, seg=10, rings=6, mat=0):
    """soft capsule between a and b (radii r0 at a, r1 at b)."""
    d = b - a
    L = d.length
    if L < 1e-6:
        return []
    y = d.normalized()
    x = y.orthogonal().normalized()
    z = y.cross(x)
    verts = []
    for i in range(rings + 1):
        t = i / rings
        c = a.lerp(b, t)
        rr = _mix(r0, r1, t)
        ring = []
        for j in range(seg):
            ang = 2 * math.pi * j / seg
            p = c + (x * math.cos(ang) + z * math.sin(ang)) * rr
            ring.append(bm.verts.new(p))
        verts.append(ring)
    faces = []
    for i in range(rings):
        for j in range(seg):
            f = bm.faces.new((verts[i][j], verts[i][(j + 1) % seg],
                              verts[i + 1][(j + 1) % seg], verts[i + 1][j]))
            f.material_index = mat
            faces.append(f)
    # end caps
    for end, ring, inward in ((a, verts[0], y), (b, verts[-1], -y)):
        mid = bm.verts.new(end - inward * (r0 if end == a else r1) * 0.15)
        for j in range(seg):
            f = bm.faces.new((ring[j], ring[(j + 1) % seg], mid))
            f.material_index = mat
            faces.append(f)
    return [v for ring in verts for v in ring]


def _add_sphere(bm, c, r, cuts=3, mat=0, scale=(1, 1, 1)):
    m = Matrix.Translation(c) @ Matrix.Diagonal((*scale, 1.0))
    geo = bmesh.ops.create_icosphere(bm, subdivisions=cuts, radius=r, matrix=m)
    for f in geo.get("faces", []):
        f.material_index = mat
    return geo["verts"]


def build_mesh(rig, mat_skin):
    """soft stylized body: rounded torso, short limbs, chubby hands, small feet."""
    H = {b.name: Vector(b.head_local) for b in rig.data.bones}
    T = {b.name: Vector(b.tail_local) for b in rig.data.bones}
    bm = bmesh.new()
    # mark limb membership for later weight hints
    part = bm.verts.layers.int.new("part")  # 0 torso, 1 L arm, 2 R arm, 3 L leg, 4 R leg, 5 headstub

    # ---- torso: soft egg from pelvis to shoulders
    pel = H["pelvis"]
    sh = H["spine_03"]
    neck = H["neck_01"]
    torso_c = Vector((0.0, 0.01, (pel.z + sh.z) * 0.5))
    # slightly narrower chest so short upper arms clear the torso in throw/cheer
    torso_rx, torso_ry, torso_rz = 0.095, 0.085, (sh.z - pel.z) * 0.55 + 0.04
    tv = _add_sphere(bm, torso_c, 1.0, cuts=4, mat=0,
                     scale=(torso_rx, torso_ry, torso_rz))
    for v in tv:
        v[part] = 0
        # softer belly out front (-Y), flat-ish back
        d = v.co - torso_c
        if d.y < 0:
            v.co.y -= 0.015 * _ss(0.0, torso_ry, -d.y)
        # narrow toward neck
        k = _ss(pel.z, sh.z + 0.02, v.co.z)
        v.co.x *= 1.0 - 0.25 * k
        v.co.y *= 1.0 - 0.15 * k

    # soft shoulder pads (keep tight so upper arms clear the torso in throw)
    for s, sx in ((1, 1.0), (2, -1.0)):
        sc = Vector((sx * 0.095, 0.0, sh.z - 0.01))
        for v in _add_sphere(bm, sc, 0.045, cuts=2, mat=0, scale=(1.05, 0.85, 0.7)):
            v[part] = 0

    # short natural neck stump (head mesh continues it)
    neck_c = Vector((0.0, 0.0, (sh.z + neck.z) * 0.5))
    for v in _add_capsule(bm, Vector((0, 0.01, sh.z - 0.01)),
                          Vector((0, -0.005, neck.z + 0.02)),
                          0.055, 0.048, seg=12, rings=4):
        v[part] = 5

    # ---- arms
    for side, sx, pcode in (("l", 1.0, 1), ("r", -1.0, 2)):
        ua = H["upperarm_" + side]
        la = H["lowerarm_" + side]
        hd = H["hand_" + side]
        ht = T["hand_" + side]
        for v in _add_capsule(bm, ua, la, 0.036, 0.032, seg=10, rings=5):
            v[part] = pcode
        for v in _add_capsule(bm, la, hd, 0.030, 0.026, seg=10, rings=5):
            v[part] = pcode
        # chubby hand (soft mitt + stubby fingers)
        for v in _add_sphere(bm, hd.lerp(ht, 0.45), 0.038, cuts=2, mat=0,
                             scale=(0.85, 1.15, 0.7)):
            v[part] = pcode
        for i in range(4):
            fc = ht + Vector((sx * (0.008 * i - 0.012), 0.012, -0.01))
            for v in _add_sphere(bm, fc, 0.012, cuts=1, mat=0, scale=(0.7, 1.2, 0.7)):
                v[part] = pcode
        # thumb
        tc = hd + Vector((sx * 0.02, 0.015, 0.005))
        for v in _add_sphere(bm, tc, 0.013, cuts=1, mat=0, scale=(0.8, 1.1, 0.7)):
            v[part] = pcode

    # ---- legs
    for side, sx, pcode in (("l", 1.0, 3), ("r", -1.0, 4)):
        th = H["thigh_" + side]
        kf = H["calf_" + side]
        ft = H["foot_" + side]
        bl = H["ball_" + side]
        for v in _add_capsule(bm, th, kf, 0.055, 0.045, seg=10, rings=5):
            v[part] = pcode
        for v in _add_capsule(bm, kf, ft, 0.040, 0.032, seg=10, rings=5):
            v[part] = pcode
        # small soft foot (slightly longer so gait heel/toe pads match probe offsets)
        foot_c = Vector((ft.x, (ft.y + bl.y) * 0.5 - 0.01, 0.02))
        for v in _add_sphere(bm, foot_c, 0.042, cuts=2, mat=0, scale=(0.65, 1.55, 0.42)):
            v[part] = pcode
            v.co.z = max(v.co.z, GROUND + 0.004)

    # merge nearby verts so capsules fuse into one soft body (less doll-joint look)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.014)
    try:
        bmesh.ops.smooth_vert(bm, verts=list(bm.verts), factor=0.35, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bmesh.ops.smooth_vert(bm, verts=list(bm.verts), factor=0.25, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    except Exception:
        pass
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    me = bpy.data.meshes.new("Body")
    bm.to_mesh(me)
    # pull part codes before free
    part_codes = [0] * len(me.vertices)
    bm.verts.ensure_lookup_table()
    # after to_mesh, indices match
    for i, v in enumerate(bm.verts):
        if i < len(part_codes):
            part_codes[i] = v[part]
    bm.free()
    me.materials.append(mat_skin)
    for p in me.polygons:
        p.use_smooth = True

    body = bpy.data.objects.new("Body", me)
    bpy.context.scene.collection.objects.link(body)
    body.parent = rig
    # vertex groups for all bones
    for b in rig.data.bones:
        body.vertex_groups.new(name=b.name)
    _auto_weight(body, rig, part_codes)
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    print("STYLIZED body tris", sum(len(p.vertices) - 2 for p in me.polygons),
          "verts", len(me.vertices))
    return body


def _auto_weight(body, rig, part_codes):
    """simple distance/part weights — good enough for soft stylized limbs."""
    H = {b.name: Vector(b.head_local) for b in rig.data.bones}
    T = {b.name: Vector(b.tail_local) for b in rig.data.bones}
    me = body.data

    def bones_for(code):
        if code == 0:
            return ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01"]
        if code == 1:
            return ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "deltoid_l"]
        if code == 2:
            return ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "deltoid_r"]
        if code == 3:
            return ["thigh_l", "calf_l", "foot_l", "ball_l"]
        if code == 4:
            return ["thigh_r", "calf_r", "foot_r", "ball_r"]
        return ["neck_01", "spine_03", "head"]

    def dist_bone(co, name):
        a, b = H[name], T[name]
        ab = b - a
        L2 = ab.length_squared + 1e-12
        t = max(0.0, min(1.0, (co - a).dot(ab) / L2))
        return (a + ab * t - co).length

    for i, v in enumerate(me.vertices):
        names = [n for n in bones_for(part_codes[i] if i < len(part_codes) else 0) if n in body.vertex_groups]
        if not names:
            names = ["pelvis"]
        dists = [(n, dist_bone(v.co, n)) for n in names]
        # softmin weights
        soft = [(n, math.exp(-d * 28.0)) for n, d in dists]
        s = sum(w for _, w in soft) + 1e-12
        for n, w in soft:
            body.vertex_groups[n].add([i], w / s, "REPLACE")
        # always a little pelvis on torso
        if (part_codes[i] if i < len(part_codes) else 0) == 0:
            body.vertex_groups["pelvis"].add([i], 0.15, "ADD")


def build_clothes(rig, body, mats):
    """soft stylized vest (with gold buttons), flower shorts, brown sandals —
    built as independent meshes weighted to the body, not MH shells."""
    H = {b.name: Vector(b.head_local) for b in rig.data.bones}
    pel_z = H["pelvis"].z
    neck_z = H["neck_01"].z
    sh_z = H["spine_03"].z
    knee_z = H["calf_l"].z

    # ---- vest: Concept A red V-neck with gold buttons (no white tank bib)
    vest = _cloth_torso(rig, body, "Vest", mats["vest"],
                        z0=pel_z + 0.05, z1=neck_z - 0.015,
                        rx=0.118, ry=0.098, open_front=0.018, v_neck=0.045,
                        solid=0.0045)
    _gold_buttons(vest, mats.get("gold") or mats["vest"],
                  [Vector((0.0, -0.100, sh_z - 0.045 - 0.032 * i)) for i in range(3)])

    # thin white undershirt only at the sides / under arms (not a front bib)
    tank = _cloth_torso(rig, body, "Tank", mats["tank"],
                        z0=pel_z + 0.04, z1=sh_z - 0.02,
                        rx=0.112, ry=0.092, open_front=0.06, v_neck=0.0,
                        solid=0.0015)

    # ---- shorts
    shorts = _shorts(rig, body, mats["shorts"], hem_z=knee_z + 0.06, waist_z=pel_z + 0.08)

    # ---- sandals
    sandals = []
    for side in ("l", "r"):
        sandals.append(_sandal(rig, side, mats["sandal"], mats.get("strap") or mats["sandal"]))

    return tank, vest, shorts, sandals


def _cloth_torso(rig, body, name, mat, z0, z1, rx, ry, open_front, v_neck, solid):
    bm = bmesh.new()
    seg, rings = 20, 8
    rings_v = []
    for i in range(rings + 1):
        t = i / rings
        z = _mix(z0, z1, t)
        # slight waist
        waist = 1.0 - 0.08 * math.sin(t * math.pi)
        rxi, ryi = rx * waist, ry * waist
        ring = []
        for j in range(seg):
            ang = 2 * math.pi * j / seg - math.pi * 0.5  # 0 = front (-Y)
            x = math.cos(ang) * rxi
            y = math.sin(ang) * ryi
            # V-neck / open front on the front half
            front = max(0.0, -y / max(ryi, 1e-6))
            if open_front > 0 and front > 0.55 and abs(x) < open_front + v_neck * t:
                continue
            if v_neck > 0 and front > 0.7 and z > z1 - v_neck * 1.2 and abs(x) < v_neck * (0.3 + 1.4 * (z - (z1 - v_neck)) / max(v_neck, 1e-6)):
                continue
            ring.append(bm.verts.new(Vector((x, y, z))))
        rings_v.append(ring)
    # connect consecutive rings by nearest angle — skip open gaps
    # simpler: rebuild as closed then delete front faces
    bm.clear()
    rings_v = []
    for i in range(rings + 1):
        t = i / rings
        z = _mix(z0, z1, t)
        waist = 1.0 - 0.08 * math.sin(t * math.pi)
        rxi, ryi = rx * waist, ry * waist
        ring = [bm.verts.new(Vector((math.cos(2 * math.pi * j / seg - math.pi * 0.5) * rxi,
                                     math.sin(2 * math.pi * j / seg - math.pi * 0.5) * ryi, z)))
                for j in range(seg)]
        rings_v.append(ring)
    for i in range(rings):
        for j in range(seg):
            bm.faces.new((rings_v[i][j], rings_v[i][(j + 1) % seg],
                          rings_v[i + 1][(j + 1) % seg], rings_v[i + 1][j]))
    # delete front V / open faces
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.y >= -0.02:
            continue
        if open_front > 0 and abs(c.x) < open_front + 0.01 + 0.04 * _ss(z0, z1, c.z):
            if c.z > z0 + 0.02:
                kill.append(f)
                continue
        if v_neck > 0 and c.z > z1 - v_neck and abs(c.x) < v_neck * 0.85:
            kill.append(f)
    if kill:
        bmesh.ops.delete(bm, geom=kill, context="FACES")
    if solid > 0:
        try:
            bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=solid)
        except Exception:
            pass
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = rig
    for bn in ("pelvis", "spine_01", "spine_02", "spine_03", "neck_01"):
        if bn not in ob.vertex_groups:
            ob.vertex_groups.new(name=bn)
    for v in me.vertices:
        z = v.co.z
        w_sp3 = _ss(z0, z1, z)
        ob.vertex_groups["spine_03"].add([v.index], 0.55 * w_sp3, "REPLACE")
        ob.vertex_groups["spine_02"].add([v.index], 0.35 * (1 - abs(w_sp3 - 0.5) * 2), "REPLACE")
        ob.vertex_groups["spine_01"].add([v.index], 0.25 * (1 - w_sp3), "REPLACE")
        ob.vertex_groups["pelvis"].add([v.index], 0.35 * (1 - w_sp3), "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return ob


def _gold_buttons(vest, mat, centres):
    """three small gold spheres on the vest front."""
    gold = bpy.data.materials.get("gold") or mat
    if gold.name not in [m.name for m in vest.data.materials if m]:
        vest.data.materials.append(gold)
    gi = next(i for i, m in enumerate(vest.data.materials) if m and m.name == gold.name)
    bm = bmesh.new()
    bm.from_mesh(vest.data)
    for c in centres:
        geo = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.009,
                                         matrix=Matrix.Translation(c))
        for f in geo.get("faces", []):
            f.material_index = gi
    bm.to_mesh(vest.data)
    me = vest.data
    for p in me.polygons:
        c = p.center
        if any((Vector(c) - bc).length < 0.016 for bc in centres) and c.y < -0.05:
            p.material_index = gi
        p.use_smooth = True
    bm.free()


def _shorts(rig, body, mat, hem_z, waist_z):
    bm = bmesh.new()
    # soft flared cylinder + crotch bridge
    seg, rings = 20, 6
    H = {b.name: Vector(b.head_local) for b in rig.data.bones}
    for side, sx in (("l", 1.0), ("r", -1.0)):
        cx = sx * 0.05
        rings_v = []
        for i in range(rings + 1):
            t = i / rings
            z = _mix(waist_z, hem_z, t)
            flare = 1.0 + 0.35 * t * t
            rx, ry = 0.07 * flare, 0.065 * flare
            ring = [bm.verts.new(Vector((cx + math.cos(2 * math.pi * j / seg) * rx,
                                         math.sin(2 * math.pi * j / seg) * ry, z)))
                    for j in range(seg)]
            rings_v.append(ring)
        for i in range(rings):
            for j in range(seg):
                bm.faces.new((rings_v[i][j], rings_v[i][(j + 1) % seg],
                              rings_v[i + 1][(j + 1) % seg], rings_v[i + 1][j]))
    # waist bridge
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.01)
    try:
        bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=0.003)
    except Exception:
        pass
    me = bpy.data.meshes.new("Shorts")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    # UV for flower pattern
    uv = me.uv_layers.new(name="UVMap")
    for p in me.polygons:
        for li, vi in zip(p.loop_indices, p.vertices):
            co = me.vertices[vi].co
            uv.data[li].uv = ((co.x + 0.2) * 2.2, (co.z - hem_z) * 3.5)
    ob = bpy.data.objects.new("Shorts", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = rig
    for bn in ("pelvis", "thigh_l", "thigh_r", "spine_01"):
        ob.vertex_groups.new(name=bn)
    for v in me.vertices:
        wl = max(0.0, 1.0 - abs(v.co.x - 0.05) * 8) * _ss(waist_z, hem_z, waist_z + hem_z - v.co.z)
        wr = max(0.0, 1.0 - abs(v.co.x + 0.05) * 8) * _ss(waist_z, hem_z, waist_z + hem_z - v.co.z)
        ob.vertex_groups["thigh_l"].add([v.index], 0.7 * wl, "REPLACE")
        ob.vertex_groups["thigh_r"].add([v.index], 0.7 * wr, "REPLACE")
        ob.vertex_groups["pelvis"].add([v.index], 0.5 * (1.0 - max(wl, wr)), "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return ob


def _sandal(rig, side, mat_sole, mat_strap):
    ft = Vector(rig.data.bones["foot_" + side].head_local)
    bl = Vector(rig.data.bones["ball_" + side].head_local)
    sx = 1.0 if side == "l" else -1.0
    bm = bmesh.new()
    # sole
    c = Vector((ft.x, (ft.y + bl.y) * 0.5, GROUND + 0.008))
    geo = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.042,
                                     matrix=Matrix.Translation(c) @ Matrix.Diagonal((0.7, 1.4, 0.22, 1.0)))
    for v in geo["verts"]:
        v.co.z = max(v.co.z, GROUND + 0.002)
    # straps
    for yoff in (-0.01, 0.025):
        a = Vector((c.x - sx * 0.025, c.y + yoff, 0.018))
        b = Vector((c.x + sx * 0.025, c.y + yoff, 0.018))
        _add_capsule(bm, a, b, 0.006, 0.006, seg=6, rings=2)
    # heel strap
    _add_capsule(bm, Vector((c.x - sx * 0.02, c.y + 0.045, 0.02)),
                 Vector((c.x + sx * 0.02, c.y + 0.045, 0.02)), 0.006, 0.006, seg=6, rings=2)
    me = bpy.data.meshes.new("Sandal_" + side)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat_sole)
    me.materials.append(mat_strap)
    for p in me.polygons:
        p.use_smooth = True
        if p.center.z > 0.014:
            p.material_index = 1
    ob = bpy.data.objects.new("Sandal_" + side, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = rig
    for bn in ("foot_" + side, "ball_" + side, "calf_" + side):
        ob.vertex_groups.new(name=bn)
    for v in me.vertices:
        ob.vertex_groups["foot_" + side].add([v.index], 0.85, "REPLACE")
        ob.vertex_groups["ball_" + side].add([v.index], 0.15, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return ob


def make_flower_shorts_texture(path, n=256):
    """soft cream hibiscus/leaf pattern on yellow — written as PNG for Godot override."""
    import numpy as np
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        # fallback raw PNG via blender later; write a simple numpy PPM-ish through bpy
        img = bpy.data.images.new("shorts_pat", n, n, alpha=False)
        px = [0.0] * (n * n * 4)
        random.seed(22)
        for y in range(n):
            for x in range(n):
                i = (y * n + x) * 4
                px[i:i+3] = [0.97, 0.82, 0.32]
                px[i+3] = 1.0
                # soft flower blobs
                for cx, cy, s in ((0.25, 0.3, 0.08), (0.7, 0.55, 0.09), (0.4, 0.75, 0.07),
                                  (0.15, 0.7, 0.06), (0.85, 0.25, 0.07), (0.55, 0.2, 0.06)):
                    d = math.hypot(x / n - cx, y / n - cy) / s
                    if d < 1.2:
                        k = max(0.0, 1.0 - d)
                        k = k * k
                        px[i] = _mix(px[i], 0.96, k * 0.85)
                        px[i+1] = _mix(px[i+1], 0.90, k * 0.85)
                        px[i+2] = _mix(px[i+2], 0.72, k * 0.85)
        img.pixels.foreach_set(px)
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        return path
    im = Image.new("RGB", (n, n), (247, 209, 82))
    dr = ImageDraw.Draw(im)
    random.seed(22)
    for _ in range(18):
        cx, cy = random.randint(10, n - 10), random.randint(10, n - 10)
        r = random.randint(14, 28)
        # petals
        for a in range(5):
            ang = a * 72 * math.pi / 180
            px = cx + int(math.cos(ang) * r * 0.55)
            py = cy + int(math.sin(ang) * r * 0.55)
            dr.ellipse((px - r // 2, py - r // 2, px + r // 2, py + r // 2),
                       fill=(245, 230, 190))
        dr.ellipse((cx - r // 3, cy - r // 3, cx + r // 3, cy + r // 3), fill=(240, 220, 160))
        # leaf
        lx, ly = cx + r, cy + r // 2
        dr.ellipse((lx - 8, ly - 4, lx + 8, ly + 4), fill=(230, 215, 170))
    im.save(path)
    return path
