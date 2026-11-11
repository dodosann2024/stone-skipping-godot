"""v16 shoulder: one continuous neck -> trapezius -> deltoid -> upper arm.

- shape: rounded deltoid cap, faint clavicle / acromion, filled axilla, smoothed blend region
- rig: a deltoid helper bone per side (child of the clavicle, at the shoulder joint) that the
  pose solver turns half way between the clavicle-carried rest arm and the upper arm, so the
  shoulder blend never spans the full arm rotation (no collapsing / pinching / candy-wrap)
- weights: torso <-> upper arm blend re-split into torso <-> helper <-> upper arm, max 4 bones
"""
import bpy, math
from mathutils import Vector

TORSO = ("clavicle", "spine_01", "spine_02", "spine_03", "neck_01")
MEDIAL_KEEP = 0.7
TRAP_IN, TRAP_OUT = -0.07, -0.005   # arm influence fades out medially over this range (x from the joint)


def _smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def _nbrs(me):
    nb = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        nb[a].append(b)
        nb[b].append(a)
    return nb


def _frames(rig):
    out = {}
    for s in "lr":
        ua = rig.data.bones["upperarm_" + s]
        j = Vector(ua.head_local)
        a = (Vector(ua.tail_local) - j).normalized()
        # medial: towards the armpit / chest centre, perpendicular to the arm
        m = Vector((-1.0 if s == "l" else 1.0, 0.0, -0.35))
        m = (m - a * m.dot(a)).normalized()
        up = (Vector((0, 0, 1)) - a * a.dot(Vector((0, 0, 1)))).normalized()
        cl = rig.data.bones["clavicle_" + s]
        out[s] = (j, a, m, up, Vector(cl.head_local))
    return out


def sculpt(rig, body):
    me = body.data
    nb = _nbrs(me)
    F = _frames(rig)
    co = [v.co.copy() for v in me.vertices]
    nrm = [v.normal.copy() for v in me.vertices]
    # region weight: a soft ball around each shoulder joint
    reg = [0.0] * len(co)
    for i, p in enumerate(co):
        for s, (j, a, m, up, ch) in F.items():
            if (p.x > 0) != (s == "l"):
                continue
            d = (p - j).length
            reg[i] = max(reg[i], 1.0 - _smoothstep(0.05, 0.10, d))
    # 1. Taubin smoothing in the region: irons out the proxy's facets without shrinking it
    for it in range(12):
        for lam in (0.5, -0.53):
            new = {}
            for i, w in enumerate(reg):
                if w <= 0.0 or not nb[i]:
                    continue
                c = sum((co[k] for k in nb[i]), Vector()) / len(nb[i])
                new[i] = co[i] + (c - co[i]) * (lam * w)
            for i, c in new.items():
                co[i] = c
    # 2. anatomy, displaced along the rest normal (metres; this is a ~9 year old)
    for i, p in enumerate(co):
        for s, (j, a, m, up, ch) in F.items():
            if (p.x > 0) != (s == "l") or (p - j).length > 0.14:
                continue
            r = p - j
            u = r.dot(a)                         # along the arm, + towards the elbow
            rad = r - a * u
            rl = rad.length
            if rl < 1e-5:
                continue
            rn = rad / rl
            off = 0.0
            # deltoid: wraps front / top / back of the arm root, not the armpit side; fullest
            # ~3 cm below the acromion, tapering into the arm by the insertion (~9 cm)
            lat = _smoothstep(-0.25, 0.55, -rn.dot(m))
            prof = math.exp(-((u - 0.028) / 0.040) ** 2) * _smoothstep(-0.045, -0.005, u)
            off += 0.0055 * lat * prof
            # anterior / posterior deltoid heads a touch fuller than the middle
            fb = abs(rn.y)
            off += 0.0015 * lat * prof * _smoothstep(0.3, 0.8, fb)
            # acromion: small firm point at the top of the shoulder, just above the joint
            top = _smoothstep(0.3, 0.8, rn.dot(up))
            off += 0.0010 * top * math.exp(-((u + 0.006) / 0.013) ** 2)
            # axilla: fill the armpit crease (anterior / posterior folds), only on the medial side
            med = _smoothstep(0.2, 0.8, rn.dot(m))
            ax = math.exp(-((u - 0.02) / 0.035) ** 2)
            off += 0.0025 * med * ax * _smoothstep(0.25, 0.75, fb)
            # clavicle: faint ridge along the front-top of the collar bone, hollow just below it
            seg = j - ch
            t = max(0.0, min(1.0, (p - ch).dot(seg) / seg.length_squared))
            q = ch + seg * t
            v = p - q
            if v.length > 1e-5 and 0.12 < t < 0.95:
                vn = v.normalized()
                ridge = Vector((0, -0.55, 0.83))
                below = Vector((0, -0.95, -0.3)).normalized()
                k = (1.0 - _smoothstep(0.85, 0.95, t))
                off += 0.0011 * k * math.exp(-(vn.angle(ridge) / 0.32) ** 2)
                off -= 0.0008 * k * math.exp(-(vn.angle(below) / 0.30) ** 2) * (1.0 - _smoothstep(0.6, 0.9, t))
            co[i] = p + nrm[i] * off
    for v, c in zip(me.vertices, co):
        v.co = c
    me.update()


def add_helpers(rig):
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    for s in "lr":
        ua = eb["upperarm_" + s]
        h = eb.new("deltoid_" + s)
        h.head = ua.head.copy()
        h.tail = ua.head + (ua.tail - ua.head) * 0.4
        h.roll = ua.roll
        h.parent = eb["clavicle_" + s]
        h.use_connect = False
        h.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")


def reweight(rig, body):
    me = body.data
    nb = _nbrs(me)
    F = _frames(rig)
    gid = {g.name: g.index for g in body.vertex_groups}
    for s in "lr":
        if "deltoid_" + s not in gid:
            gid["deltoid_" + s] = body.vertex_groups.new(name="deltoid_" + s).index
    name = {i: n for n, i in gid.items()}
    W = [{name[e.group]: e.weight for e in v.groups if e.weight > 0.0} for v in me.vertices]
    touched = set()
    for s, (j, a, m, up, ch) in F.items():
        ua = "upperarm_" + s
        torso = [n + ("_" + s if n == "clavicle" else "") for n in TORSO]
        # arm fraction of the torso/arm blend, smoothed so the band is even all round the shoulder
        reg = {}
        for i, v in enumerate(me.vertices):
            if (v.co.x > 0) != (s == "l") or (v.co - j).length > 0.13:
                continue
            wu = W[i].get(ua, 0.0)
            wt = sum(W[i].get(n, 0.0) for n in torso)
            if wu + wt > 1e-4 and wt > 0.0 or wu > 0.0 and (v.co - j).length < 0.09:
                reg[i] = (wu, wt)
        f = {i: (wu / (wu + wt) if wu + wt > 0 else 0.0) for i, (wu, wt) in reg.items()}
        for it in range(4):
            new = {}
            for i in f:
                ks = [k for k in nb[i] if k in f]
                if ks:
                    new[i] = f[i] * 0.5 + sum(f[k] for k in ks) / len(ks) * 0.5
            f.update(new)
        # MPFB lets the upper arm pull on the trapezius all the way to the neck; the top of the
        # shoulder medial to the acromion belongs to the collar bone (and the vest strap with it)
        for i in f:
            p = me.vertices[i].co
            dx = abs(p.x) - abs(j.x)
            top = _smoothstep(j.z - 0.01, j.z + 0.03, p.z)
            f[i] *= 1.0 - top * (1.0 - _smoothstep(TRAP_IN, TRAP_OUT, dx))
        for i, (wu, wt) in reg.items():
            tot = wu + wt
            if tot <= 1e-4:
                continue
            fr = min(max(f[i], 0.0), 1.0)
            if fr <= 0.5:
                h, nu, nt = 2 * fr, 0.0, 1 - 2 * fr
            else:
                h, nu, nt = 2 - 2 * fr, 2 * fr - 1, 0.0
            # the armpit keeps part of the direct blend: a half-turned axilla balloons out when the
            # arm goes overhead, the top of the shoulder is where the volume has to be kept
            r = me.vertices[i].co - j
            rad = r - a * r.dot(a)
            k = 1.0 - MEDIAL_KEEP * _smoothstep(0.0, 0.7, rad.normalized().dot(m)) if rad.length > 1e-5 else 1.0
            h, nu, nt = h * k, nu * k + (1 - k) * fr, nt * k + (1 - k) * (1 - fr)
            sc = (nt * tot / wt) if wt > 0 else 0.0
            for n in torso:
                if n in W[i]:
                    W[i][n] *= sc
            if wt <= 0 and nt > 0:
                W[i]["clavicle_" + s] = nt * tot
            W[i][ua] = nu * tot
            W[i]["deltoid_" + s] = h * tot
            touched.add(i)
    # max 4 influences, normalised
    for i in touched:
        ws = sorted(((w, n) for n, w in W[i].items() if w > 1e-4), reverse=True)[:4]
        tot = sum(w for w, n in ws)
        for n in list(W[i]):
            body.vertex_groups[n].remove([i])
        for w, n in ws:
            body.vertex_groups[n].add([i], w / tot, "REPLACE")
    print("SHOULDER reweighted", len(touched))

