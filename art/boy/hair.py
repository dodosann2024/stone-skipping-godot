"""v17 hair: a soft, slightly tousled textured crop built from layered hair cards over a thin scalp cap.

- cap: a thin shell of the scalp (no bald gaps between cards), with a soft broken hairline;
- cards: strand clumps grown over the scalp along a groom field (whorl at the crown, a light fringe swept
  to his right, sides and nape falling down), in an inner / main / outer layer plus a few flyaways.
  Each card is a ribbon with the strand atlas (textures/hair_strands.png, tools/hair_texture.py) mapped
  root (v = 0) to tip (v = 1). Its normals are bent towards the scalp normal so the hair lights as a soft
  volume, not as flat cards;
- everything fits under the straw hat (it keeps its v16 size) and stays off the skin and ears.

Per-vertex data for shaders/hair.gdshader (material "hair"):
  UV        card: atlas u / root-to-tip v;  cap: angle round the crown / distance from it
  UV2 (Face) x: card sway weight (0 root .. 1 tip), cap: distance to the hairline (0..1)
             y: card inner-layer occlusion (0 outer .. 0.6 inner), cap: 1
  "cb"      1 where the hair is under the hat crown (no sway there while he wears it) -> COLOR.b
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix, noise
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

COLS = 4
SEED = 23


def _ss(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def in_hair(q):
    """scalp region; q = point - head joint (metres, Blender axes: -Y is the face side, +X his left)"""
    x, y, z = abs(q.x), q.y, q.z
    if z < -0.03:
        return False
    if y < -0.07:
        # forehead: the hairline rises a little towards the temples
        return z > 0.076 + 0.016 * min(x / 0.055, 1.0) ** 2
    if y < -0.05:
        # sideburns in front of the ears
        return z > (0.032 if x > 0.055 else 0.076)
    if x > 0.058 and y <= -0.008:
        # above the ear only
        return z > 0.054
    # behind the ears and the nape, the hairline rising towards the sides
    return z > -0.018 + 0.6 * max(0.0, x - 0.03)


def _grow_ok(q):
    """where hair may hang to: above the brows, over the top of the ears, a little past the nape"""
    x, y, z = abs(q.x), q.y, q.z
    if y < -0.07:
        return z > 0.062
    if x > 0.05 and y < -0.008:
        return z > (0.036 if y > -0.05 else 0.024)
    return z > -0.028 + 0.6 * max(0.0, x - 0.03)


class Hat:
    """the straw hat's crown and brim in its own (untilted) frame, from build_boy.hat()"""

    def __init__(self, info, margin=0.004):
        self.piv = Vector(info["piv"])
        self.rot = Matrix.Rotation(math.radians(info["tilt"]), 3, "X")
        self.inv = self.rot.transposed()
        self.cy, self.rx, self.ry, self.base = info["cy"], info["rx"], info["ry"], info["base_z"]
        self.prof = [tuple(p) for p in info["prof"]]
        self.m = margin

    def local(self, p):
        l = self.inv @ (p - self.piv) + self.piv
        return Vector((l.x / self.rx, (l.y - self.cy) / self.ry, l.z - self.base))

    def world(self, l):
        p = Vector((l.x * self.rx, l.y * self.ry + self.cy, l.z + self.base))
        return self.rot @ (p - self.piv) + self.piv

    def crown_r(self, z):
        """crown radius (normalised) at height z above the band"""
        cr = [p for p in self.prof if p[1] >= 0.0]
        cr.sort(key=lambda p: p[1])
        if z <= cr[0][1]:
            return cr[0][0]
        for (s0, z0), (s1, z1) in zip(cr, cr[1:]):
            if z <= z1:
                return s0 + (s1 - s0) * (z - z0) / max(z1 - z0, 1e-6)
        return 0.0

    def brim_z(self, s):
        br = [p for p in self.prof if p[1] <= 0.0]
        br.sort(key=lambda p: p[0])
        if s <= br[0][0]:
            return br[0][1]
        for (s0, z0), (s1, z1) in zip(br, br[1:]):
            if s <= s1:
                return z0 + (z1 - z0) * (s - s0) / max(s1 - s0, 1e-6)
        return br[-1][1]

    def under(self, p):
        l = self.local(p)
        return l.z > -0.004 and math.hypot(l.x, l.y) < 1.02

    def fit(self, p):
        """move p inside the crown / under the brim (with margin); returns the new point"""
        l = self.local(p)
        s = math.hypot(l.x, l.y)
        ms = self.m / min(self.rx, self.ry)
        if l.z > -0.002:
            # inside the crown, below its top
            top = max(self.prof[0][1] - self.m, 0.0)
            if l.z > top:
                l.z = top
            r = self.crown_r(l.z) - ms
            if s > r and s > 1e-6:
                l.x *= r / s
                l.y *= r / s
            elif s >= 1.0 - ms:
                pass
        elif s > 0.98:
            # under the brim
            zb = self.brim_z(s) - 0.002 - self.m
            if l.z > zb:
                l.z = zb
        return self.world(l)


def _groups(src, dl, fi, loc):
    fv = src.faces[fi].verts
    bw = poly_3d_calc([u.co for u in fv], loc)
    acc = {}
    for u, w in zip(fv, bw):
        for g, x in u[dl].items():
            acc[g] = acc.get(g, 0.0) + w * x
    return {g: x for g, x in acc.items() if x > 1e-4}


def build(rig, body, hat_info, mat):
    J = {b.name: Vector(b.head_local) for b in rig.data.bones}
    hc = J["head"]
    rnd = random.Random(SEED)
    hat = Hat(hat_info)
    src = bmesh.new()
    src.from_mesh(body.data)
    src.faces.ensure_lookup_table()
    src.verts.ensure_lookup_table()
    dl_src = src.verts.layers.deform.active
    bvh = BVHTree.FromBMesh(src)

    def near(p):
        loc, n, fi, d = bvh.find_nearest(p)
        return loc, n, fi

    # crown whorl, on the scalp a little behind the top of the head
    wl, wn, _ = near(hc + Vector((0.008, 0.03, 0.16)))
    W = wl

    def flow(p, n):
        q = p - hc
        d = p - W
        d -= n * d.dot(n)
        if d.length < 1e-6:
            d = Vector((0.0, -1.0, 0.0))
        d.normalize()
        g = Vector((0.0, 0.0, -1.0))
        g -= n * g.dot(n)
        top = _ss(0.09, 0.13, q.z)
        front = _ss(-0.03, -0.07, q.y)
        d = d + g * (0.15 + 0.6 * (1.0 - top)) * (1.0 - 0.6 * front)
        # light fringe swept towards his right (-X)
        d += Vector((-0.45, 0.0, 0.0)) * front
        r = (p - W).length
        d += n.cross(d.normalized()) * 0.9 * math.exp(-r / 0.025)
        d -= n * d.dot(n)
        return d.normalized()

    # ---------------------------------------------------------------- cap
    bm = bmesh.new()
    bm.from_mesh(body.data)
    keep = set(f for f in bm.faces if in_hair(f.calc_center_median() - hc))
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
    for _ in range(2):
        lone = [f for f in bm.faces if sum(1 for e in f.edges if e.is_boundary) >= 3]
        bmesh.ops.delete(bm, geom=lone, context="FACES")
    bm.verts.ensure_lookup_table()
    # distance to the hairline over the cap (Dijkstra-ish along edges)
    dist = {v: (0.0 if any(e.is_boundary for e in v.link_edges) else 1e9) for v in bm.verts}
    front = [v for v in bm.verts if dist[v] == 0.0]
    while front:
        nxt = []
        for v in front:
            for e in v.link_edges:
                o = e.other_vert(v)
                dd = dist[v] + e.calc_length()
                if dd < dist[o] - 1e-7:
                    dist[o] = dd
                    nxt.append(o)
        front = nxt
    bm.normal_update()
    for v in bm.verts:
        v.co = v.co + v.normal * 0.0012
    cap_faces = [f for f in bm.faces]
    # width of the broken hairline: 6 mm, and a longer, uneven fade at the nape (a tapered short cut)
    hl_w = {}
    for v in bm.verts:
        q = v.co - hc
        nk = _ss(0.0, 0.05, q.y) * (1.0 - _ss(0.0, 0.045, q.z))
        hl_w[v] = 0.006 + 0.012 * nk * (0.75 + 0.5 * (noise.noise(q * 90.0) * 0.5 + 0.5))
    # cap UVs: angle round the crown (in the scalp's tangent frame at the whorl) and distance from it
    ax = wn.normalized()
    e1 = ax.orthogonal().normalized()
    e2 = ax.cross(e1)
    while len(bm.loops.layers.uv):
        bm.loops.layers.uv.remove(bm.loops.layers.uv[0])
    uvl = bm.loops.layers.uv.new("UVMap")
    fl = bm.loops.layers.uv.new("Face")
    for f in cap_faces:
        us = []
        for lp in f.loops:
            d = lp.vert.co - W
            us.append(math.atan2(d.dot(e2), d.dot(e1)) / (2 * math.pi) + 0.5)
        if max(us) - min(us) > 0.5:
            us = [u + 1.0 if u < 0.5 else u for u in us]
        for lp, u in zip(f.loops, us):
            lp[uvl].uv = (u, (lp.vert.co - W).length * 10.0)
            lp[fl].uv = (min(dist[lp.vert] / hl_w[lp.vert], 1.0), 1.0)
    dl = bm.verts.layers.deform.active

    # ---------------------------------------------------------------- roots
    tris = []
    for f in cap_faces:
        vs = [v.co for v in f.verts]
        for i in range(1, len(vs) - 1):
            a, b, c = vs[0], vs[i], vs[i + 1]
            tris.append((a, b, c, (b - a).cross(c - a).length * 0.5))
    total = sum(t[3] for t in tris)
    cum = []
    acc = 0.0
    for t in tris:
        acc += t[3]
        cum.append(acc)
    import bisect

    def sample():
        x = rnd.random() * total
        a, b, c, _ = tris[min(bisect.bisect_left(cum, x), len(tris) - 1)]
        u, v = rnd.random(), rnd.random()
        if u + v > 1:
            u, v = 1 - u, 1 - v
        return a + (b - a) * u + (c - a) * v

    cand = [sample() for _ in range(9000)]

    def poisson(r, pts):
        cell = r
        grid = {}
        out = []
        for p in pts:
            k = (int(p.x // cell), int(p.y // cell), int(p.z // cell))
            ok = True
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for dz in (-1, 0, 1):
                        for o in grid.get((k[0] + dx, k[1] + dy, k[2] + dz), ()):
                            if (o - p).length < r:
                                ok = False
                                break
                        if not ok:
                            break
                    if not ok:
                        break
                if not ok:
                    break
            if ok:
                grid.setdefault(k, []).append(p)
                out.append(p)
        return out

    # [name, poisson radius, width, length scale, lift scale, tilt, columns, occlusion, sway]
    layers = [
        ("inner", 0.0125, 0.013, 0.85, 0.45, 0.15, (0,), 0.55, 0.5),
        ("main", 0.0105, 0.010, 1.0, 1.0, 0.3, (0, 1), 0.25, 0.9),
        ("outer", 0.0150, 0.0085, 1.08, 1.45, 0.5, (1, 2), 0.0, 1.0),
        ("fly", 0.0300, 0.0060, 1.15, 1.9, 0.9, (3,), 0.0, 1.3),
    ]
    cards = []
    for li, (name, r, w, ls, lfs, tilt, cols, occ, sway) in enumerate(layers):
        pts = cand[:]
        rnd.shuffle(pts)
        for p in poisson(r, pts):
            cards.append((li, p))

    # ---------------------------------------------------------------- cards
    nverts = len(bm.verts)
    hatk = {}
    ncards = 0
    for li, p in cards:
        name, r, w, ls, lfs, tilt, cols, occ, sway = layers[li]
        loc, n, fi = near(p)
        q = loc - hc
        top = _ss(0.085, 0.125, q.z)
        frontk = _ss(-0.035, -0.075, q.y)
        back = _ss(0.0, 0.05, q.y)
        low = 1.0 - _ss(0.02, 0.07, q.z)
        ear = _ss(0.055, 0.075, abs(q.x)) * (1.0 - _ss(0.05, 0.08, q.z))
        nz = noise.noise(q * 60.0) * 0.5 + 0.5
        # the nape tapers like a short cut: the cap's fine strands carry the hairline, with the cards above
        # thinning out into a few short wisps (a full set of short cards there reads as rows of scales)
        napek = back * (1.0 - _ss(0.0, 0.045, q.z))
        if (li == 0 and napek > 0.25) or (li == 1 and rnd.random() < 1.2 * napek):
            continue
        # lengths: textured top, a light fringe, short sides / nape / sideburns
        L = 0.016 + (0.040 - 0.016) * top
        L = L + (0.034 - L) * frontk * _ss(0.07, 0.1, q.z)
        L *= 1.0 - 0.3 * low * back - 0.3 * ear - 0.35 * low * (1.0 - back)
        L *= ls * (0.8 + 0.4 * nz) * rnd.uniform(0.9, 1.1) * (1.0 - 0.3 * napek)
        lift = (0.0015 + 0.0045 * top) * (1.0 - 0.4 * low)
        lift = lift * lfs * rnd.uniform(0.7, 1.3)
        h0 = 0.0018 + (0.0012 if li > 0 else 0.0) + 0.0008 * li
        nseg = max(2, min(5, int(round(L / 0.011))))
        yaw = rnd.uniform(-0.3, 0.3) * (1.0 if li < 2 else 1.6)
        pts = []
        nrm = []
        cur = loc
        d = None
        for k in range(nseg + 1):
            t = k / nseg
            sl, sn, _ = near(cur)
            if k > 0 and ((sl - cur).length > 0.02 or not _grow_ok(sl - hc)):
                break
            h = h0 + lift * (1.0 - (1.0 - t) ** 2) + 0.0015 * t ** 3 * (1.0 + top)
            pts.append(sl + sn * h)
            nrm.append(sn)
            fd = flow(sl, sn)
            fd = Matrix.Rotation(yaw, 3, sn) @ fd
            d = fd if d is None else (d * 0.55 + fd * 0.45)
            d -= sn * d.dot(sn)
            d.normalize()
            cur = sl + d * (L / nseg)
        if len(pts) < 3:
            continue
        # fit under the hat and off the skin
        for i in range(len(pts)):
            pts[i] = hat.fit(pts[i])
            sl, sn, _ = near(pts[i])
            if (pts[i] - sl).dot(sn) < 0.0012:
                pts[i] = sl + sn * 0.0012
        # short cards (nape, sideburns, over the ears) narrower: a square card reads as a scale, not a tuft
        narrow = 0.6 + 0.4 * _ss(0.012, 0.03, L)
        col = 2 if napek > 0.35 and li < 3 else rnd.choice(cols)
        flip = rnd.random() < 0.5
        u0, u1 = (col + 1) / COLS, col / COLS
        if flip:
            u0, u1 = u1, u0
        th = rnd.uniform(-tilt, tilt)
        vrow = []
        m = len(pts) - 1
        for i, (pp, sn) in enumerate(zip(pts, nrm)):
            t = i / m
            dirv = (pts[min(i + 1, m)] - pts[max(i - 1, 0)]).normalized()
            side = sn.cross(dirv).normalized()
            side = Matrix.Rotation(th, 3, dirv) @ side
            half = 0.5 * w * narrow * rnd.uniform(0.9, 1.1) * (1.0 - 0.3 * t) if i == 0 else half_prev * (1.0 - 0.3 / m)
            half_prev = half
            a = bm.verts.new(pp - side * half)
            b = bm.verts.new(pp + side * half)
            for v in (a, b):
                v[dl].clear()
                for g, x in _groups(src, dl_src, near(pp)[2], near(pp)[0]).items():
                    v[dl][g] = x
                hatk[v] = 1.0 if hat.under(pp) else 0.0
            vrow.append((a, b, t, sn))
        for i in range(m):
            a0, b0, t0, _ = vrow[i]
            a1, b1, t1, _ = vrow[i + 1]
            f = bm.faces.new((a0, b0, b1, a1))
            for lp in f.loops:
                v = lp.vert
                isb = v in (b0, b1)
                t = t0 if v in (a0, b0) else t1
                lp[uvl].uv = (u1 if isb else u0, 1.0 - t)
                lp[fl].uv = (t ** 1.5 * sway, occ)
        ncards += 1
    bm.verts.index_update()
    hatk = {v.index: k for v, k in hatk.items()}
    me = bpy.data.meshes.new("Hair")
    bm.to_mesh(me)
    bm.free()
    src.free()
    ob = bpy.data.objects.new("Hair", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = body.parent
    for g in body.vertex_groups:
        ob.vertex_groups.new(name=g.name)
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = body.parent
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    # under-hat flag and bent normals: cap keeps its own; cards lean on the scalp normal
    att = me.attributes.new("cb", "FLOAT", "POINT")
    kv = [0.0] * len(me.vertices)
    for i, k in hatk.items():
        kv[i] = k
    # cap vertices
    for i in range(nverts):
        co = me.vertices[i].co
        kv[i] = 1.0 if hat.under(co) else 0.0
    att.data.foreach_set("value", kv)
    nb = []
    centre = hc + Vector((0.0, 0.005, 0.07))
    for v in me.vertices:
        if v.index < nverts:
            nb.append(v.normal.copy())
        else:
            sl, sn, _ = near(v.co)
            radial = (v.co - centre).normalized()
            nb.append((sn * 0.6 + radial * 0.4).normalized())
    me.normals_split_custom_set_from_vertices(nb)
    print("HAIR cap verts", nverts, "cards", ncards, "tris", sum(len(p.vertices) - 2 for p in me.polygons))
    return ob
