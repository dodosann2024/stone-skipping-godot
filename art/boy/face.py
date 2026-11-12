"""v22 face: a young child's head (MakeHuman's own age model) on the body, MakeHuman modelling targets and a
few smooth lenses for a cute, stylised look (big round eyes, button nose, small mouth), real eyeballs,
expression morphs baked from the MakeHuman expression units, a mouth interior, and a painted detail map
(brows, lash line, lips, blush) in the head's front projection (UV2).

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
SUB = {"eye": "eyes", "cheek": "cheek", "ear": "ears", "measure": "neck"}

# the head is a young child's (MakeHuman's own age model, ~6 years) on the body, see child_head(); on top
# ("LR-" = both sides): big open eyes a little apart, a short button nose with a lifted tip, a small
# smiling mouth, full cheeks, a small chin, rounded ears
CHILD_AGE, CHILD_SCALE = 0.05, 1.28
SHAPE = {
    "LR-eye-scale-incr": 1.4, "LR-eye-height2-incr": 0.7, "LR-eye-height1-incr": 0.25, "LR-eye-trans-out": 0.3,
    "nose-scale-vert-decr": 0.5, "nose-scale-horiz-decr": 0.5, "nose-point-up": 1.0, "nose-hump-decr": 0.7,
    "nose-scale-depth-decr": 0.3,
    "mouth-scale-horiz-decr": 0.32, "mouth-angles-up": 0.45, "mouth-lowerlip-volume-incr": 0.3,
    "chin-height-decr": 0.3,
    "LR-ear-shape-round": 0.6,
    "measure-neck-height-decr": 0.6, "neck-scale-horiz-decr": 0.3,
}


def _mix(ob):
    """shape-key mix of the base mesh (all vertices, helpers included)"""
    kb = ob.data.shape_keys.key_blocks
    n = len(ob.data.vertices)
    b = np.zeros(n * 3)
    kb["Basis"].data.foreach_get("co", b)
    out, t = b.copy(), np.zeros(n * 3)
    for k in kb[1:]:
        if k.value != 0.0 and not k.mute:
            k.data.foreach_get("co", t)
            out += k.value * (t - b)
    return b.reshape(-1, 3), out.reshape(-1, 3)


def _centroid(ob, co, g):
    gi = ob.vertex_groups[g].index
    return co[[v.index for v in ob.data.vertices if any(e.group == gi for e in v.groups)]].mean(0)


def child_head(base, macro):
    """swap the head for a young child's (same base mesh made at CHILD_AGE, scaled CHILD_SCALE about the
    head joint), blended into the body by the rig's head / neck skin weights"""
    from bl_ext.user_default.mpfb.services.humanservice import HumanService
    m = dict(macro)
    m["age"] = CHILD_AGE
    ch = HumanService.create_human(macro_detail_dict=m, scale=0.1)
    _, C = _mix(ch)
    jc = _centroid(ch, C, "joint-head")
    for o in [c for c in bpy.data.objects if c.parent == ch] + [ch]:
        bpy.data.objects.remove(o)
    groups = {g.name for g in base.vertex_groups}
    rig = HumanService.add_builtin_rig(base, "game_engine")
    B, T = _mix(base)
    jt = _centroid(base, T, "joint-head")
    hg, ng = base.vertex_groups["head"].index, base.vertex_groups["neck_01"].index
    w = np.zeros(len(T))
    for v in base.data.vertices:
        for e in v.groups:
            if e.group == hg:
                w[v.index] += e.weight
            elif e.group == ng:
                w[v.index] += 0.5 * e.weight
    w = np.clip(w, 0.0, 1.0)
    mw = base.matrix_world.copy()
    base.parent = None
    base.matrix_world = mw
    for o in [c for c in bpy.data.objects if c.parent == rig] + [rig]:
        bpy.data.objects.remove(o)
    for g in list(base.vertex_groups):
        if g.name not in groups:
            base.vertex_groups.remove(g)
    for md in list(base.modifiers):
        if md.type == "ARMATURE":
            base.modifiers.remove(md)
    D = (jt + CHILD_SCALE * (C - jc) - T) * w[:, None]
    k = base.shape_key_add(name="child_head", from_mix=False)
    k.data.foreach_set("co", (B + D).ravel())
    k.value = 1.0
    print("CHILD HEAD age %.2f scale %.2f, moved %d vertices, max %.1f mm" % (CHILD_AGE, CHILD_SCALE, int((w > 0).sum()), np.linalg.norm(D, axis=1).max() * 1000))


# stylisation on top of the targets: (strength, radius m) of a smooth radial lens; > 0 magnifies about the
# centre (the eyes: the eyeballs sit on the helper vertices, so they grow with their sockets), < 0 shrinks.
# Monotonic (no fold) for -1 < a < 1.25.
# The eye lens opens the lids more vertically (third value: z factor) so the eyes go round; the eyeballs
# (helper vertices) scale evenly and stay spheres, and the eye region sinks back by a fraction (fourth
# value) of what the balls grew, so the bigger eyes don't bulge. The nose shrinks about a point behind its
# tip (so the upper lip doesn't follow it forward) and is smoothed into a button; the mouth region sits
# back (muzzle: metres, radius). Below the cheekbones the face narrows towards a small chin (taper:
# fraction of the width at the chin, how far the lower cheeks sit back in m), the chin shrinks (lens), the
# lower face is shorter (lift: fraction) and the neck slims (fraction). Rings round the eyes (clear of the lid rims) are smoothed: no creases or bags.
CUTE = {"eye": (0.35, 0.036, 1.55, 0.25), "nose": (-0.45, 0.017), "mouth": (-0.12, 0.02), "muzzle": (0.004, 0.03),
        "taper": (0.18, 0.006), "chin": (-0.22, 0.018), "neck": 0.32, "lift": 0.1, "under": (0.004, 0.022),
        "smooth": 16}


def _ss_np(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _bump(r):
    return np.where(r < 1.0, (1.0 - np.minimum(r, 1.0) ** 2) ** 2, 0.0)


def _lens(T, c, a, R, sz=1.0):
    d = T - c
    g = _bump(np.linalg.norm(d, axis=1) / R)
    return d * (a * g)[:, None] * np.array([1.0, 1.0, sz])


def _skin_mask(base):
    if "body" in base.vertex_groups:
        gi = base.vertex_groups["body"].index
        m = np.zeros(len(base.data.vertices), bool)
        m[[v.index for v in base.data.vertices if any(e.group == gi for e in v.groups)]] = True
        return m
    hg = {g.index for g in base.vertex_groups if g.name.startswith(("helper-", "joint-"))}
    return np.array([not any(e.group in hg for e in v.groups) for v in base.data.vertices])


def _taubin(P, ed, mov, n, lam=0.6, mu=-0.63):
    deg = np.bincount(ed.ravel(), minlength=len(P)).astype(float)
    m = (mov & (deg > 0))[:, None]
    for i in range(2 * n):
        acc = np.zeros_like(P)
        np.add.at(acc, ed[:, 0], P[ed[:, 1]])
        np.add.at(acc, ed[:, 1], P[ed[:, 0]])
        avg = acc / np.maximum(deg, 1.0)[:, None]
        P = P + (lam if i % 2 == 0 else mu) * (avg - P) * m
    return P


def _form(base, T, P, ball, eyes, ez, tip, mc, nk, ed, f):
    """project the head toward a soft Pixar/chibi silhouette while keeping eye/mouth topology"""
    skin = _skin_mask(base)
    ax = nk[1]
    head = skin & (P[:, 2] > nk[2] - 0.04) & (np.hypot(P[:, 0], P[:, 1] - ax) < 0.17)
    # target half-width (m) vs height relative to the eyes: round forehead, soft cheeks, small chin
    # (dz_mm, half_width_m)
    prof = np.array([
        [70, 0.068], [50, 0.072], [30, 0.074], [10, 0.076], [0, 0.078],
        [-15, 0.074], [-30, 0.066], [-45, 0.054], [-60, 0.042], [-75, 0.030], [-90, 0.022],
    ], float)
    dz = (P[:, 2] - ez) * 1000.0
    tw = np.interp(dz, prof[::-1, 0], prof[::-1, 1])
    rxy = np.hypot(P[:, 0], P[:, 1] - ax)
    # keep eyes/lips, reshape the rest of the face shell
    keep = ball.copy()
    for c in eyes:
        keep |= np.linalg.norm(P - c, axis=1) < 0.018
    keep |= np.linalg.norm(P - mc, axis=1) < 0.016
    # below the forehead only — the cranium stays put so the hat still seats
    faceband = _ss_np(ez + 0.025, ez + 0.005, P[:, 2])
    amt = f.get("amt", 0.55) * head * (~keep) * _ss_np(0.02, 0.05, rxy) * faceband
    # lateral narrow toward target half-width (never widen)
    hx = np.maximum(np.abs(P[:, 0]), 1e-6)
    scale = np.minimum(1.0, tw / hx)
    P2 = P.copy()
    P2[:, 0] = P[:, 0] * (1.0 - amt + amt * scale)
    # soft cheeks: pull the forward mid-face a little back below the eyes (less swollen)
    cheek = amt * _ss_np(ez + 0.005, ez - 0.01, P[:, 2]) * _ss_np(ez - 0.07, ez - 0.055, P[:, 2])
    cheek *= _ss_np(0.02, 0.055, np.abs(P[:, 0])) * _ss_np(ax - 0.02, ax - 0.07, P[:, 1])
    P2[:, 1] += 0.006 * cheek
    # button nose tip: small forward+up bulge after the shrink
    tip2 = tip + np.array([0.0, -0.0015, 0.0015])
    g = _bump(np.linalg.norm(P - tip2, axis=1) / 0.009)
    P2 += np.array([0.0, -0.0018, 0.0012])[None, :] * (g * (~ball))[:, None]
    # slim neck again after reshape
    zn = _ss_np(nk[2] - 0.04, nk[2] + 0.0, P2[:, 2]) * _ss_np(mc[2] - 0.01, mc[2] - 0.03, P2[:, 2])
    r2 = np.hypot(P2[:, 0], P2[:, 1] - ax)
    wn = f.get("neck", 0.2) * zn * _ss_np(0.08, 0.055, r2) * head
    P2[:, 0] -= P2[:, 0] * wn
    P2[:, 1] -= (P2[:, 1] - ax) * wn
    e2 = ed[head[ed[:, 0]] & head[ed[:, 1]]]
    mov = head & (~ball) & (np.linalg.norm(P - tip, axis=1) > 0.01)
    P2 = _taubin(P2, e2, mov, f.get("iters", 40))
    if os.environ.get("CUTE_DEBUG"):
        for dzz in range(-80, 70, 10):
            z = ez + dzz / 1000.0
            b = head & (np.abs(P2[:, 2] - z) < 0.003)
            if b.sum():
                print("FORM z %+4d halfw %.1f" % (dzz, np.abs(P2[b, 0]).max() * 1000))
    return P2


def cute(base, cfg=None):
    cfg = cfg or CUTE
    B, T = _mix(base)
    D = np.zeros_like(T)
    eyes = [_centroid(base, T, "joint-%s-eye" % s) for s in "lr"]
    ball = np.zeros(len(T), bool)
    for s in "lr":
        gi = base.vertex_groups["helper-%s-eye" % s].index
        ball[[v.index for v in base.data.vertices if any(e.group == gi for e in v.groups)]] = True
    a, R, sz, back = cfg["eye"]
    for c in eyes:
        D += np.where(ball[:, None], _lens(T, c, a, R), _lens(T, c, a, R, sz))
        rb = np.linalg.norm(T[ball] - c, axis=1)
        rb = np.median(rb[rb < R])
        D[:, 1] += back * a * rb * _bump(np.linalg.norm(T - c, axis=1) / R)
        # fill under the eye: the cheek top comes forward so the bigger socket leaves no hollow below it
        fu, ru = cfg["under"]
        cu = c + np.array([0.0, 0.0, -0.75 * R])
        D[:, 1] -= fu * _bump(np.linalg.norm((T - cu) * np.array([0.8, 1.0, 1.4]), axis=1) / ru) * ~ball \
            * _ss_np(c[2] - 0.4 * R, c[2] - 0.65 * R, T[:, 2])
    ez = sum(c[2] for c in eyes) / 2
    cand = np.where((np.abs(T[:, 0]) < 0.004) & (T[:, 2] < ez - 0.012) & (T[:, 2] > ez - 0.06))[0]
    tip = T[cand[np.argmin(T[cand, 1])]]
    D += _lens(T, tip + np.array([0.0, 0.008, 0.004]), *cfg["nose"])
    # small soft button tip (forward + slightly up) so the nose isn't a shadow blob
    tip2 = tip + np.array([0.0, -0.002, 0.001])
    D += _lens(T, tip2, 0.22, 0.008)
    D[:, 2] += 0.0012 * _bump(np.linalg.norm(T - tip2, axis=1) / 0.01) * ~ball
    mc = _centroid(base, T, "joint-mouth")
    D += _lens(T, mc, *cfg["mouth"])
    # the mouth and the chin sit back a little: a flat lower face
    sb, rm = cfg["muzzle"]
    r = np.linalg.norm((T - mc) * np.array([1.0, 0.5, 1.0]), axis=1) / rm
    D[:, 1] += sb * _bump(r) * (T[:, 1] < mc[1] + 0.01)
    # heart-shaped lower face: narrower from the cheekbones down to a small chin, the lower cheeks a little
    # back; then a slimmer neck. Each level scales evenly about the head's axis, so nothing folds.
    nk = _centroid(base, T, "joint-neck")
    zc, zchin = ez - 0.015, mc[2] - 0.03
    rxy = np.hypot(T[:, 0], T[:, 1] - nk[1])
    near = _ss_np(0.13, 0.1, rxy)
    kt, kb = cfg["taper"]
    tz = _ss_np(zc, zchin, T[:, 2]) * _ss_np(zchin - 0.03, zchin - 0.008, T[:, 2])
    D[:, 0] -= T[:, 0] * kt * tz * near
    front = _ss_np(nk[1] - 0.02, nk[1] - 0.06, T[:, 1])
    D[:, 1] += kb * tz * front * _ss_np(0.012, 0.04, np.abs(T[:, 0])) * near
    zn = _ss_np(nk[2] - 0.035, nk[2] + 0.0, T[:, 2]) * _ss_np(zchin - 0.0, zchin - 0.02, T[:, 2])
    wn = cfg["neck"] * zn * _ss_np(0.085, 0.06, rxy)
    D[:, 0] -= T[:, 0] * wn
    D[:, 1] -= (T[:, 1] - nk[1]) * wn
    # a short lower face (eyes nearer the middle of the head): below the eyes everything rises toward
    # them, by a fraction of the distance, down to the chin; the neck takes up the difference
    kz = cfg["lift"]
    zf = ez - 0.006
    lz = np.where(T[:, 2] >= zchin, kz * np.maximum(zf - T[:, 2], 0.0) * _ss_np(zf, zf - 0.012, T[:, 2]),
                  kz * (zf - zchin) * _ss_np(nk[2], zchin, T[:, 2]))
    D[:, 2] += lz * near
    cz = T[np.where((np.abs(T[:, 0]) < 0.004) & (np.abs(T[:, 2] - zchin) < 0.006) & ~ball)[0]]
    chin = np.array([0.0, cz[:, 1].min() + 0.012, zchin + 0.004])
    D += _lens(T, chin, *cfg["chin"])
    P = T + D
    wt = np.zeros(len(T))
    for c in eyes:
        r = np.linalg.norm(T - c, axis=1) / R
        wt = np.maximum(wt, _ss_np(0.5, 0.65, r) * (1.0 - _ss_np(0.95, 1.2, r)))
    wt = np.maximum(wt, 0.7 * _ss_np(0.02, 0.012, np.linalg.norm(T - tip, axis=1)))
    wt[ball] = 0.0
    ed = np.zeros(len(base.data.edges) * 2, int)
    base.data.edges.foreach_get("vertices", ed)
    ed = ed.reshape(-1, 2)
    deg = np.bincount(ed.ravel(), minlength=len(T)).astype(float)
    for _ in range(cfg.get("smooth", 0)):
        acc = np.zeros_like(P)
        np.add.at(acc, ed[:, 0], P[ed[:, 1]])
        np.add.at(acc, ed[:, 1], P[ed[:, 0]])
        avg = acc / np.maximum(deg, 1.0)[:, None]
        P += 0.5 * wt[:, None] * (avg - P) * (deg > 0)[:, None]
    D = P - T
    if cfg.get("form") is not None:
        P = _form(base, T, P, ball, eyes, ez, tip, mc, nk, ed, cfg["form"])
        D = P - T
    if os.environ.get("CUTE_DEBUG"):
        for nm, c in (("eye", eyes[0]), ("tip", tip), ("mouth", mc), ("chin", chin), ("neck", nk)):
            i = np.argmin(np.linalg.norm(T - c, axis=1))
            print("DBG %s z %.1f -> %.1f  y %.1f -> %.1f" % (nm, T[i, 2] * 1000, P[i, 2] * 1000, T[i, 1] * 1000, P[i, 1] * 1000))
        m = (np.abs(T[:, 0]) < 0.003) & (T[:, 1] < nk[1] - 0.03) & ~ball
        print("DBG lowest front midline z %.1f -> %.1f" % (T[m, 2].min() * 1000, P[m, 2].min() * 1000))
    k = base.shape_key_add(name="cute", from_mix=False)
    k.data.foreach_set("co", (B + D).ravel())
    k.value = 1.0
    print("CUTE", cfg, "max %.1f mm" % (np.linalg.norm(D, axis=1).max() * 1000))


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
        w = 0.0011 + 0.0012 * _ss(0.0, 0.6, t)
        B = np.maximum(B, (1.0 - _ss(w * 0.55, w, d)) * 0.75)
        wing = [oc, (oc[0] + s * 0.0032, oc[1] + 0.0016)]
        d2, t2 = _seg_dist(PX, PY, wing)
        B = np.maximum(B, (1.0 - _ss(0.0001, 0.0011 * (1.0 - t2) + 0.0001, d2)) * 0.85)
        # soft upper lashes (short strokes lifting off the lid)
        for _ in range(28):
            tt = rnd.random() ** 0.7
            c0 = (ic[0] + (oc[0] - ic[0]) * tt, ic[1] + (oc[1] - ic[1]) * tt
                  + 0.0012 + 0.0010 * math.sin(math.pi * tt))
            ang = math.radians(55.0 + 40.0 * tt + rnd.gauss(0, 8))
            ln = rnd.uniform(0.0016, 0.0028)
            c1 = (c0[0] + s * math.cos(ang) * ln * 0.35, c0[1] + math.sin(ang) * ln)
            ds, ts = _seg_dist(PX, PY, [c0, c1])
            B = np.maximum(B, (1.0 - _ss(0.00005, 0.00022, ds)) * (0.55 + 0.25 * np.sin(np.pi * ts)) * (0.55 + 0.35 * tt))
        # lid crease, a soft shadow above the lid
        cr = [(p[0], p[1] + 0.0036 + 0.0008 * math.sin(math.pi * min(1.0, (abs(p[0]) - abs(ic[0])) / (abs(oc[0]) - abs(ic[0]))))) for p in up]
        d3, t3 = _seg_dist(PX, PY, cr)
        B = np.maximum(B, np.exp(-(d3 / 0.0007) ** 2) * 0.12 * _ss(0.05, 0.3, t3) * (1.0 - _ss(0.85, 1.0, t3)))
        # lower lid: a faint line and a little shadow
        d4, t4 = _seg_dist(PX, PY, lo)
        B = np.maximum(B, (1.0 - _ss(0.0001, 0.0003, d4)) * 0.02 * _ss(0.15, 0.5, t4) * (1.0 - _ss(0.7, 0.95, t4)))
        # brow: a soft, short, rounded arch well above the eye (a child's brows are light and gentle)
        xin, xout = abs(ic[0]) - 0.0005, abs(oc[0]) + 0.0025
        def brow(t):
            b = math.sin(min(max(t * 0.9 + 0.08, 0.0), 1.0) * math.pi) ** 0.8
            return (s * (xin + (xout - xin) * t), top + 0.0085 + 0.0035 * b)
        cl = [brow(i / 40.0) for i in range(41)]
        db, tb = _seg_dist(PX, PY, cl)
        hw = 0.0022 * (1.0 - tb) ** 0.7 + 0.0008 * tb
        fill = (1.0 - _ss(hw * 0.4, hw * 1.2, db)) * (0.6 - 0.25 * tb) * _ss(0.0, 0.12, tb)
        R = np.maximum(R, fill)
        for _ in range(260):
            t = rnd.random() ** 0.85
            c = brow(t)
            h = 0.0016 * (1.0 - t) ** 0.7 + 0.0006 * t
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
            R[j0:j1, i0:i1] = np.minimum(1.0, R[j0:j1, i0:i1] + k * 0.3)
        # cheek warmth
        A = np.maximum(A, _gauss(PX, PY, (cx + s * 0.012, marks[s]["cy"] - 0.038), (0.02, 0.014)) * 0.4)
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
    B = np.maximum(B, crease * 0.12)
    A = np.maximum(A, _gauss(PX, PY, (mx, line[len(line) // 2][1]), (0.016, 0.011)) * 0.25)
    # nose: the tip (most forward point near the middle) and the nostrils (underside, facing down)
    nose = [v for v in me.vertices if abs(v.co.x) < 0.004 and hz + 0.0 < v.co.z < marks[1]["cy"] + hz]
    tip = min(nose, key=lambda v: v.co.y).co
    A = np.maximum(A, _gauss(PX, PY, uv(tip), (0.0055, 0.0050)) * 0.28)
    A = np.maximum(A, _gauss(PX, PY, (0.0, (uv(tip)[1] + marks[1]["cy"]) * 0.5), (0.004, 0.012)) * 0.22)
    for s in (1, -1):
        ns = [v.co for v in me.vertices if 0.0015 < v.co.x * s < 0.014 and tip.z - 0.016 < v.co.z < tip.z and v.normal.z < -0.45 and v.co.y < tip.y + 0.016]
        if ns:
            c = sum(ns, Vector()) / len(ns)
            B = np.maximum(B, _gauss(PX, PY, uv(c), (0.0026, 0.0014)) * 0.12)
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
