"""v21 face: MakeHuman modelling targets for the look, real eyeballs, expression morphs baked from the
MakeHuman expression units, a mouth interior, and a painted detail map (brows, lash line, lips, blush) in
the head's front projection (UV2).

Expression offsets ride through the build as per-vertex FLOAT_VECTOR attributes ("ex_<name>") on Body; at
export the face region is split off into a small skinned mesh (BoyHead) that carries them as shape keys,
so only ~2k vertices pay for the morphs in Godot.
"""
import bpy, bmesh, os, math, random
import numpy as np
from mathutils import Vector
from bl_ext.user_default.mpfb.services.targetservice import TargetService
from bl_ext.user_default.mpfb.services.clothesservice import ClothesService
from bl_ext.user_default.mpfb.entities.clothes.mhclo import Mhclo

TG = os.path.expanduser("~/.config/blender/4.5/extensions/user_default/mpfb/data/targets/")
RACE = {"asian": 0.5, "caucasian": 0.4, "african": 0.1}
SUB = {"eye": "eyes", "cheek": "cheek", "ear": "ears"}

# modelling targets ("LR-" = both sides): an oval face with a defined chin and cheekbones, a straight
# narrow nose with a proper bridge, open eyes set a little closer, full lips with lifted corners, flat ears
SHAPE = {
    "head-oval": 0.5, "chin-prominent-incr": 0.3, "chin-bones-incr": 0.25, "chin-height-decr": 0.45, "mouth-trans-up": 0.3,
    "mouth-scale-horiz-decr": 0.15,
    "LR-cheek-bones-incr": 0.6, "LR-cheek-volume-decr": 0.45,
    "nose-hump-decr": 0.3, "nose-point-width-decr": 0.35, "nose-scale-vert-incr": 0.2, "nose-greek-incr": 0.3,
    "nose-nostrils-width-decr": 0.2, "nose-flaring-decr": 0.25, "nose-scale-depth-incr": 0.3,
    "LR-eye-scale-incr": 1.0, "LR-eye-height2-incr": 0.3, "LR-eye-trans-in": 0.9, "LR-eye-corner1-up": 0.2,
    "eyebrows-trans-down": 0.2, "eyebrows-trans-forward": 0.3,
    "mouth-upperlip-volume-incr": 0.25, "mouth-lowerlip-volume-incr": 0.3, "mouth-cupidsbow-incr": 0.4,
    "mouth-angles-up": 0.35, "LR-ear-flap-decr": 0.3,
}

# morph -> expression units ("blink" is made by blink(): the units' lid closure barely moves this proxy's rims)
EXPR = {
    "squint": {"eye-left-slit": 1.0, "eye-right-slit": 1.0},
    "smile": {"mouth-corner-puller": 1.0},
    "open": {"mouth-open": 1.0},
    "frown": {"mouth-depression": 1.0},
    "press": {"mouth-compression": 1.0},
    "brow_up": {"eyebrows-left-up": 1.0, "eyebrows-right-up": 1.0},
    "brow_in": {"eyebrows-left-inner-up": 1.0, "eyebrows-right-inner-up": 1.0},
    "brow_down": {"eyebrows-left-down": 1.0, "eyebrows-right-down": 1.0},
}
EPS = 5e-5          # smaller offsets are dropped, so the morph region ends exactly


def _key(base, path, w):
    k = TargetService.load_target(base, path, weight=0.0)
    k.slider_max = max(1.0, w)
    k.value = w
    return k


def shape(base):
    for name, w in SHAPE.items():
        for n in ([name.replace("LR-", "l-"), name.replace("LR-", "r-")] if name.startswith("LR-") else [name]):
            p = n.split("-")
            d = p[1] if p[0] in ("l", "r") else p[0]
            _key(base, TG + SUB.get(d, d) + "/" + n + ".target.gz", w)


def bake(base, px, proxy_file):
    """proxy-vertex offsets of every expression: the units are base-mesh targets, so refit the proxy"""
    mh = Mhclo()
    mh.load(proxy_file)
    mh.clothes = px

    def fit():
        ClothesService.fit_clothes_to_human(px, base, mhclo=mh, set_parent=False)
        return [v.co.copy() for v in px.data.vertices]
    rest = fit()
    out = {}
    for name, units in EXPR.items():
        keys = [_key(base, TG + "expression/units/%s/%s.target.gz" % (r, u), w * f)
                for u, w in units.items() for r, f in RACE.items()]
        co = fit()
        out[name] = [c - r for c, r in zip(co, rest)]
        for k in keys:
            base.shape_key_remove(k)
    fit()
    return rest, out


def subdivided(ob, rest, offsets):
    """the offsets after one Catmull-Clark level (same topology as the body's baked subsurf)"""
    def sub(co):
        me = ob.data.copy()
        me.vertices.foreach_set("co", [x for c in co for x in c])
        tmp = bpy.data.objects.new("_sub", me)
        bpy.context.scene.collection.objects.link(tmp)
        tmp.modifiers.new("sub", "SUBSURF").levels = 1
        ev = tmp.evaluated_get(bpy.context.evaluated_depsgraph_get())
        r = [v.co.copy() for v in ev.data.vertices]
        bpy.data.objects.remove(tmp)
        bpy.data.meshes.remove(me)
        return r
    r0 = sub(rest)
    return {n: [a - b for a, b in zip(sub([r + d for r, d in zip(rest, off)]), r0)] for n, off in offsets.items()}


def _sphere(pts):
    """least-squares sphere through points -> centre, radius"""
    P = np.array([tuple(p) for p in pts])
    A = np.c_[2.0 * P, np.ones(len(P))]
    c, *_ = np.linalg.lstsq(A, (P * P).sum(1), rcond=None)
    return Vector(c[:3]), math.sqrt(c[3] + Vector(c[:3]).length_squared)


def blink(body, eyes_ob):
    """the lids turn about the eyeball's horizontal axis (keeping their distance to the ball, so they slide
    over it): the upper rim comes down to a third above the lower rim, the lower rim rises to meet it;
    the turn fades out over the lid toward the crease / the cheek"""
    me = body.data
    cnt = {}
    for p in me.polygons:
        for k in p.edge_keys:
            cnt[k] = cnt.get(k, 0) + 1
    loops = sorted(_loops([k for k, c in cnt.items() if c == 1 and all(me.vertices[i].co.y < -0.03 for i in k)]),
                   key=lambda l: -sum(me.vertices[i].co.z for i in l) / len(l))[:2]
    out = [Vector() for _ in me.vertices]
    for l in loops:
        side = 1.0 if me.vertices[l[0]].co.x > 0 else -1.0
        c, R = _sphere([v.co for v in eyes_ob.data.vertices if v.co.x * side > 0])
        ang = lambda p: math.atan2(p.z - c.z, -(p.y - c.y))
        up, lo = lip_chains(l, lambda i: me.vertices[i].co)
        ux = [me.vertices[i].co.x for i in up]
        uphi = [ang(me.vertices[i].co) for i in up]
        lx = [me.vertices[i].co.x for i in lo]
        lphi = [ang(me.vertices[i].co) for i in lo]
        xa, xb = min(ux), max(ux)
        for v in me.vertices:
            d = v.co - c
            if d.y > 0.0 or not (xa - 0.004 < v.co.x < xb + 0.004) or d.length > R + 0.012:
                continue
            phi = ang(v.co)
            pu = float(np.interp(v.co.x, ux, uphi))
            pl = float(np.interp(v.co.x, lx, lphi))
            pc = pl + 0.33 * (pu - pl)
            if phi >= pu - 0.03:
                t = max(0.0, phi - pu) / 0.5
                dphi = (pc - 0.01 - pu) * (1.0 - float(_ss(0.0, 1.0, t)))
            elif phi <= pl + 0.03:
                t = max(0.0, pl - phi) / 0.32
                dphi = (pc - pl) * (1.0 - float(_ss(0.0, 1.0, t)))
            else:
                continue
            r = math.hypot(d.y, d.z)
            dphi *= 1.0 - float(_ss(R + 0.004, R + 0.012, d.length))
            p2 = phi + dphi
            out[v.index] = Vector((0.0, c.y - r * math.cos(p2) - v.co.y, c.z + r * math.sin(p2) - v.co.z))
    print("BLINK eyeball r %.1f mm, lid travel %.1f mm" % (R * 1000, max(o.length for o in out) * 1000))
    return out


def store(body, offsets):
    me = body.data
    for name, off in offsets.items():
        assert len(off) == len(me.vertices), (name, len(off), len(me.vertices))
        a = me.attributes.new("ex_" + name, "FLOAT_VECTOR", "POINT")
        a.data.foreach_set("vector", [x for d in off for x in (d if d.length > EPS else (0.0, 0.0, 0.0))])
    print("EXPR", {n: round(max(d.length for d in off) * 1000, 1) for n, off in offsets.items()}, "mm")


def eyes(px_eyes, mat):
    ob = px_eyes
    ob.name = "Eyes"
    ob.data.name = "Eyes"
    for m in list(ob.modifiers):
        ob.modifiers.remove(m)
    ob.parent = None
    ob.vertex_groups.clear()
    bpy.context.view_layer.objects.active = ob
    m = ob.modifiers.new("sub", "SUBSURF")
    m.levels = 1
    bpy.ops.object.modifier_apply(modifier="sub")
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def eye_centres(ob):
    out = {}
    for s in (1, -1):
        vs = [v.co for v in ob.data.vertices if v.co.x * s > 0]
        out[s] = sum(vs, Vector()) / len(vs)
    return out


def lip_chains(loop, co):
    """an ordered closed loop around the mouth -> (upper, lower) chains from corner to corner, by x"""
    i0 = min(range(len(loop)), key=lambda i: co(loop[i]).x)
    loop = loop[i0:] + loop[:i0]
    i1 = max(range(len(loop)), key=lambda i: co(loop[i]).x)
    a, b = loop[:i1 + 1], loop[i1:] + loop[:1]
    za = sum(co(v).z for v in a) / len(a)
    zb = sum(co(v).z for v in b) / len(b)
    up, lo = (a, b) if za > zb else (b, a)
    return sorted(up, key=lambda v: co(v).x), sorted(lo, key=lambda v: co(v).x)


def mouth_cap(bm, faces, mat_index):
    """the mouth slit cap: own material; UV0 = (across the mouth, 1 on the upper lip .. 0 on the lower)"""
    fs = set(faces)
    edges = [e for f in faces for e in f.edges if any(g not in fs for g in e.link_faces)]
    loop = _loops([(e.verts[0].index, e.verts[1].index) for e in edges])[0]
    bm.verts.ensure_lookup_table()
    co = lambda i: bm.verts[i].co
    up, lo = lip_chains(loop, co)
    upper = set(up) - {up[0], up[-1]}
    x0, x1 = co(up[0]).x, co(up[-1]).x
    uv = bm.loops.layers.uv[0]
    for f in faces:
        f.material_index = mat_index
        for l in f.loops:
            l[uv].uv = ((l.vert.co.x - x0) / (x1 - x0), 1.0 if l.vert.index in upper else 0.0)
    return loop


# ------------------------------------------------------------------ painted detail map

N = 512
RECT = (-0.075, -0.085, 0.15, 0.18)     # x0, y0, width, height in UV2 (metres from the head joint)


def _loops(edges):
    """boundary edges -> ordered vertex loops"""
    nb = {}
    for a, b in edges:
        nb.setdefault(a, []).append(b)
        nb.setdefault(b, []).append(a)
    seen, out = set(), []
    for s in nb:
        if s in seen:
            continue
        loop, prev, cur = [s], None, s
        seen.add(s)
        while True:
            nxt = [n for n in nb[cur] if n != prev and n not in seen]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            seen.add(cur)
            loop.append(cur)
        out.append(loop)
    return out


def _seg_dist(px, py, pts):
    """distance from grid points to a polyline, and the polyline parameter (0..1 by length) there"""
    best = np.full(px.shape, 1e9)
    tb = np.zeros(px.shape)
    L = [0.0]
    for i in range(len(pts) - 1):
        L.append(L[-1] + math.dist(pts[i], pts[i + 1]))
    for i in range(len(pts) - 1):
        ax, ay = pts[i]
        bx, by = pts[i + 1]
        dx, dy = bx - ax, by - ay
        ll = dx * dx + dy * dy + 1e-12
        u = np.clip(((px - ax) * dx + (py - ay) * dy) / ll, 0.0, 1.0)
        d = np.hypot(px - ax - u * dx, py - ay - u * dy)
        m = d < best
        best = np.where(m, d, best)
        tb = np.where(m, (L[i] + u * (L[i + 1] - L[i])) / max(L[-1], 1e-9), tb)
    return best, tb


def _ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _gauss(px, py, c, s):
    return np.exp(-(((px - c[0]) / s[0]) ** 2 + ((py - c[1]) / s[1]) ** 2))


def paint(body, rig, path):
    me = body.data
    hz = rig.data.bones["head"].head_local.z
    uv = lambda co: (co.x, co.z - hz)
    skin = {i for i, m in enumerate(me.materials) if m and m.name == "skin"}
    cnt = {}
    for p in me.polygons:
        if p.material_index in skin:
            for k in p.edge_keys:
                cnt[k] = cnt.get(k, 0) + 1
    bnd = [k for k, c in cnt.items() if c == 1 and all(me.vertices[i].co.z > hz and me.vertices[i].co.y < -0.04 for i in k)]
    eye_loops = [l for l in _loops(bnd) if len(l) > 6]
    eye_loops.sort(key=lambda l: me.vertices[l[0]].co.x)
    assert len(eye_loops) == 2, len(eye_loops)
    gx = RECT[0] + (np.arange(N) + 0.5) / N * RECT[2]
    gy = RECT[1] + (np.arange(N) + 0.5) / N * RECT[3]
    PX, PY = np.meshgrid(gx, gy)            # row 0 = bottom (Blender image rows)
    R = np.zeros((N, N)); G = np.zeros((N, N)); B = np.zeros((N, N)); A = np.zeros((N, N))
    rnd = random.Random(21)
    marks = {}
    for loop in eye_loops:
        pts = [uv(me.vertices[i].co) for i in loop]
        s = 1.0 if pts[0][0] > 0 else -1.0
        ic = min(pts, key=lambda p: abs(p[0]))
        oc = max(pts, key=lambda p: abs(p[0]))
        def above(p):
            t = (abs(p[0]) - abs(ic[0])) / (abs(oc[0]) - abs(ic[0]))
            return p[1] > ic[1] + (oc[1] - ic[1]) * t
        up = sorted([p for p in pts if above(p)] + [ic, oc], key=lambda p: abs(p[0]))
        lo = sorted([p for p in pts if not above(p)] + [ic, oc], key=lambda p: abs(p[0]))
        top = max(p[1] for p in pts)
        cx = (ic[0] + oc[0]) * 0.5
        marks[s] = {"inner": ic, "outer": oc, "top": top, "cx": cx, "cy": (top + min(p[1] for p in pts)) * 0.5}
        # upper lash line: thin at the inner corner, fuller outward, a short lifted wing
        d, t = _seg_dist(PX, PY, up)
        w = 0.00035 + 0.00055 * _ss(0.0, 0.75, t)
        B = np.maximum(B, (1.0 - _ss(w * 0.55, w, d)) * 0.92)
        wing = [oc, (oc[0] + s * 0.0024, oc[1] + 0.0010)]
        d2, t2 = _seg_dist(PX, PY, wing)
        B = np.maximum(B, (1.0 - _ss(0.0001, 0.00065 * (1.0 - t2) + 0.0001, d2)) * 0.75)
        # lid crease, a soft shadow above the lid
        cr = [(p[0], p[1] + 0.0032 + 0.0006 * math.sin(math.pi * min(1.0, (abs(p[0]) - abs(ic[0])) / (abs(oc[0]) - abs(ic[0]))))) for p in up]
        d3, t3 = _seg_dist(PX, PY, cr)
        B = np.maximum(B, np.exp(-(d3 / 0.0007) ** 2) * 0.22 * _ss(0.05, 0.3, t3) * (1.0 - _ss(0.85, 1.0, t3)))
        # lower lid: a faint line and a little shadow
        d4, t4 = _seg_dist(PX, PY, lo)
        B = np.maximum(B, (1.0 - _ss(0.0001, 0.0003, d4)) * 0.25 * _ss(0.1, 0.5, t4))
        # brow: centreline from the inner corner past the outer one, arched at ~2/3
        xin, xout = abs(ic[0]) - 0.0022, abs(oc[0]) + 0.0045
        def brow(t):
            b = math.sin(min(t / 0.66, 1.0) * math.pi * 0.5) if t < 0.66 else 1.0 - 0.75 * ((t - 0.66) / 0.34) ** 1.5
            return (s * (xin + (xout - xin) * t), top + 0.0078 + 0.0040 * b)
        cl = [brow(i / 40.0) for i in range(41)]
        db, tb = _seg_dist(PX, PY, cl)
        hw = 0.0021 * (1.0 - tb) ** 0.8 + 0.0006 * tb
        fill = (1.0 - _ss(hw * 0.55, hw * 1.15, db)) * (0.55 - 0.25 * tb)
        R = np.maximum(R, fill)
        for _ in range(420):
            t = rnd.random() ** 0.85
            c = brow(t)
            h = 0.0021 * (1.0 - t) ** 0.8 + 0.0006 * t
            v = rnd.uniform(-1.0, 1.0) * h * 0.95
            c0 = (c[0], c[1] + v)
            # hairs point up at the brow head, then lie outward along the brow, the tail droops
            ang = math.radians(75.0 * (1.0 - float(_ss(0.0, 0.22, t))) + 12.0 - 26.0 * max(0.0, t - 0.66) / 0.34 + rnd.gauss(0, 6))
            ln = rnd.uniform(0.0022, 0.0036) * (1.0 - 0.35 * t)
            c1 = (c0[0] + s * math.cos(ang) * ln, c0[1] + math.sin(ang) * ln)
            x0, x1 = min(c0[0], c1[0]) - 0.0005, max(c0[0], c1[0]) + 0.0005
            y0, y1 = min(c0[1], c1[1]) - 0.0005, max(c0[1], c1[1]) + 0.0005
            i0, i1 = np.searchsorted(gx, x0), np.searchsorted(gx, x1)
            j0, j1 = np.searchsorted(gy, y0), np.searchsorted(gy, y1)
            sx, sy = PX[j0:j1, i0:i1], PY[j0:j1, i0:i1]
            ds, ts = _seg_dist(sx, sy, [c0, c1])
            k = (1.0 - _ss(0.00008, 0.00024, ds)) * (0.55 + 0.45 * np.sin(np.pi * ts))
            R[j0:j1, i0:i1] = np.minimum(1.0, R[j0:j1, i0:i1] + k * 0.45)
        # cheek warmth
        A = np.maximum(A, _gauss(PX, PY, (cx + s * 0.007, marks[s]["cy"] - 0.024), (0.0135, 0.0085)) * 0.8)
    # mouth: the inner lip line from the cap; lips drawn around it
    chains = lip_chains(list(body["mouth_idx"]), lambda i: me.vertices[i].co)
    edge = [[uv(me.vertices[i].co) for i in c] for c in chains]
    xl, xr = edge[0][0][0], edge[0][-1][0]
    mx, w = (xl + xr) * 0.5, (xr - xl) * 0.5 + 0.0012
    xs = np.linspace(xl, xr, 41)
    # the slit's loop runs inside the mouth; seen from the front the lips part at its upper edge
    ys = np.interp(xs, [p[0] for p in edge[0]], [p[1] for p in edge[0]]) - 0.0004
    print("LIPS upper edge %.4f lower edge %.4f (middle)" % tuple(float(np.interp(mx, [p[0] for p in e], [p[1] for p in e])) for e in edge))
    line = list(zip(xs, ys))
    yl = np.interp(PX, [p[0] for p in line], [p[1] for p in line])
    xn = (PX - mx) / w
    inside = np.clip(1.0 - xn * xn, 0.0, 1.0)
    fu = inside ** 0.55 * (1.0 - 0.22 * np.exp(-(xn / 0.16) ** 2))
    yu = yl + 0.0062 * fu
    ylo = yl - 0.0100 * inside ** 0.5
    e = 0.0011
    lips = np.where(PY > yl, 1.0 - _ss(yu - e, yu + e, PY), _ss(ylo - e, ylo + e, PY) * 0.85)
    lips *= 1.0 - _ss(0.82, 1.02, np.abs(xn))
    G = np.maximum(G, lips)
    crease = (1.0 - _ss(0.00015, 0.0005, np.abs(PY - yl))) * (1.0 - _ss(0.9, 1.05, np.abs(xn)))
    B = np.maximum(B, crease * 0.5)
    for s in (1, -1):
        B = np.maximum(B, _gauss(PX, PY, (mx + s * (w - 0.0008), np.interp(mx + s * (w - 0.0012), [p[0] for p in line], [p[1] for p in line])), (0.0012, 0.0009)) * 0.35)
    A = np.maximum(A, _gauss(PX, PY, (mx, line[len(line) // 2][1]), (0.016, 0.011)) * 0.25)
    # nose: the tip (most forward point near the middle) and the nostrils (underside, facing down)
    nose = [v for v in me.vertices if abs(v.co.x) < 0.004 and hz + 0.0 < v.co.z < marks[1]["cy"] + hz]
    tip = min(nose, key=lambda v: v.co.y).co
    A = np.maximum(A, _gauss(PX, PY, uv(tip), (0.0065, 0.0065)) * 0.6)
    A = np.maximum(A, _gauss(PX, PY, (0.0, (uv(tip)[1] + marks[1]["cy"]) * 0.5), (0.004, 0.012)) * 0.22)
    for s in (1, -1):
        ns = [v.co for v in me.vertices if 0.0015 < v.co.x * s < 0.014 and tip.z - 0.016 < v.co.z < tip.z and v.normal.z < -0.45 and v.co.y < tip.y + 0.016]
        if ns:
            c = sum(ns, Vector()) / len(ns)
            B = np.maximum(B, _gauss(PX, PY, uv(c), (0.0024, 0.0012)) * 0.55)
            marks.setdefault("nostrils", []).append(uv(c))
    marks["tip"] = uv(tip)
    marks["mouth"] = (mx, line[len(line) // 2][1], w)
    img = np.stack([R, G, B, A], axis=-1).astype(np.float32)
    im = bpy.data.images.new("face_detail", N, N, alpha=True, float_buffer=False)
    im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(np.clip(img, 0.0, 1.0).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    print("FACE MAP", path, {k: v for k, v in marks.items() if k != 1 and k != -1}, "eyes", {k: marks[k] for k in (1, -1)})
    return marks


# ------------------------------------------------------------------ export: split the morphing face off

def split_head(body):
    """faces touching any expression offset (skin + mouth) -> "BoyHead" with shape keys; custom normals on
    both sides of the cut keep the seam invisible"""
    me = body.data
    names = [n for n in ["blink"] + list(EXPR) if "ex_" + n in me.attributes]
    off = {n: np.zeros(len(me.vertices) * 3) for n in names}
    for n in names:
        me.attributes["ex_" + n].data.foreach_get("vector", off[n])
    mov = np.zeros(len(me.vertices), bool)
    for n in names:
        mov |= np.linalg.norm(off[n].reshape(-1, 3), axis=1) > 0.0
    mats = {i for i, m in enumerate(me.materials) if m and m.name in ("skin", "mouth")}
    sel = [p.index for p in me.polygons if p.material_index in mats and any(mov[v] for v in p.vertices)]
    # corner normals of the whole body, before the cut
    n0 = np.zeros(len(me.loops) * 3)
    me.corner_normals.foreach_get("vector", n0)
    a = me.attributes.new("n0", "FLOAT_VECTOR", "CORNER")
    a.data.foreach_set("vector", n0)
    head = body.copy()
    head.data = me.copy()
    bpy.context.scene.collection.objects.link(head)
    head.name = head.data.name = "BoyHead"
    sel = set(sel)
    for ob, drop in ((body, lambda i: i in sel), (head, lambda i: i not in sel)):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if drop(f.index)], context="FACES")
        bm.to_mesh(ob.data)
        bm.free()
    for ob in (body, head):
        m = ob.data
        cnt = {}
        for p in m.polygons:
            for k in p.edge_keys:
                cnt[k] = cnt.get(k, 0) + 1
        seam = {v for k, c in cnt.items() if c == 1 for v in k}
        nn = np.zeros(len(m.loops) * 3)
        m.attributes["n0"].data.foreach_get("vector", nn)
        nn = nn.reshape(-1, 3)
        vi = np.zeros(len(m.loops), int)
        m.loops.foreach_get("vertex_index", vi)
        keep = np.array([v in seam for v in vi])
        if ob is head:
            nn[~keep] = 0.0     # zero = automatic, so the morphs still bend the normals inside
        m.normals_split_custom_set([tuple(x) for x in nn])
        m.attributes.remove(m.attributes["n0"])
    hm = head.data
    head.shape_key_add(name="Basis")
    co = np.zeros(len(hm.vertices) * 3)
    hm.vertices.foreach_get("co", co)
    for n in names:
        d = np.zeros(len(hm.vertices) * 3)
        hm.attributes["ex_" + n].data.foreach_get("vector", d)
        k = head.shape_key_add(name=n)
        k.data.foreach_set("co", co + d)
    for ob in (body, head):
        for n in names:
            at = ob.data.attributes.get("ex_" + n)
            if at:
                ob.data.attributes.remove(at)
    print("HEAD SPLIT", len(hm.vertices), "verts", len(hm.polygons), "faces, morphs", names)
    return head
