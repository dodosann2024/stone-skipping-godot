"""v22 hair: a soft, stylised little-boy cut - solid locks (no cards, no alpha) over a smooth hair mass.

- mass: a shell of the scalp with a smoothed hairline, thicker away from it; on its own it is the short,
  neat sides and back;
- locks: broad, flat, softly pointed clumps grown along a groom field (whorl at the crown): a few long
  bangs rooted well back from the forehead that fall over it, swept a little to his right, and the locks
  over the crown (seen when the hat is off). Normals lean on the head's volume, so the hair lights as one
  soft shape with the locks reading on it;
- everything fits under the straw hat and stays off the skin and ears. The regions are drawn for the v21
  head and scale with the head (K).

Per-vertex data for shaders/hair.gdshader (material "hair"):
  UV        lock: round the lock (0..1) / root-to-tip (0..1);  mass: angle round the crown / 0
  UV2 (Face) x: sway weight (0 root .. 1 tip; 0 on the mass), y: 1 on the mass, 0 on the locks
  "cb"      1 where the hair is under the hat crown (no sway there while he wears it) -> COLOR.b
"""
import bpy, bmesh, math, random, bisect
from mathutils import Vector, Matrix, noise
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

SEED = 22
REF_RX = 0.0805     # hat ring half-width on the v21 head the regions below were drawn for


def _ss(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def in_hair(q):
    """scalp region; q = (point - head joint) / K (metres, Blender axes: -Y is the face side, +X his left)"""
    x, y, z = abs(q.x), q.y, q.z
    if z < -0.03:
        return False
    if y < -0.07:
        # forehead: the hairline rises a little towards the temples
        return z > 0.08 + 0.014 * min(x / 0.055, 1.0) ** 2
    if y < -0.05:
        # sideburns in front of the ears
        return z > (0.04 if x > 0.055 else 0.08)
    if x > 0.058 and y <= -0.008:
        # above the ear only
        return z > 0.056
    # behind the ears and the nape, the hairline rising towards the sides
    return z > -0.012 + 0.6 * max(0.0, x - 0.03)


def _grow_ok(q):
    """where a lock may reach: the fringe stops above the brows, the sides above the ears, a little past the nape"""
    x, y, z = abs(q.x), q.y, q.z
    if y < -0.07:
        return z > 0.066
    if x > 0.05 and y < -0.008:
        return z > (0.042 if y > -0.05 else 0.03)
    return z > -0.024 + 0.6 * max(0.0, x - 0.03)


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
    K = hat_info["rx"] / REF_RX
    rel = lambda p: (p - hc) / K
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
    wl, wn, _ = near(hc + Vector((0.008, 0.03, 0.16)) * K)
    W = wl

    def flow(p, n):
        q = rel(p)
        d = p - W
        d -= n * d.dot(n)
        if d.length < 1e-6:
            d = Vector((0.0, -1.0, 0.0))
        d.normalize()
        g = Vector((0.0, 0.0, -1.0))
        g -= n * g.dot(n)
        top = _ss(0.09, 0.13, q.z)
        front = _ss(-0.03, -0.07, q.y)
        d = d + g * (0.25 + 0.8 * (1.0 - top)) * (1.0 - 0.3 * front)
        # the fringe falls over the forehead, swept a little towards his right (-X)
        d += Vector((-0.25, 0.0, 0.0)) * front
        r = (p - W).length
        d += n.cross(d.normalized()) * 0.9 * math.exp(-r / (0.025 * K))
        d -= n * d.dot(n)
        return d.normalized()

    # ---------------------------------------------------------------- mass
    bm = bmesh.new()
    bm.from_mesh(body.data)
    keep = set(f for f in bm.faces if in_hair(rel(f.calc_center_median())))
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
    for _ in range(2):
        lone = [f for f in bm.faces if sum(1 for e in f.edges if e.is_boundary) >= 3]
        bmesh.ops.delete(bm, geom=lone, context="FACES")
    # the cut follows the body's faces: relax the hairline into a smooth curve on the scalp
    bnd = [v for v in bm.verts if v.is_boundary]
    for _ in range(12):
        new = {}
        for v in bnd:
            nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(nb) == 2:
                new[v] = v.co * 0.5 + (nb[0].co + nb[1].co) * 0.25
        for v, c in new.items():
            v.co = near(c)[0]
    bm.verts.ensure_lookup_table()
    # distance to the hairline over the mass (Dijkstra-ish along edges)
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
    cap_off = lambda d: (0.0006 + 0.0034 * _ss(0.0, 0.014 * K, d)) * K
    for v in bm.verts:
        v.co = hat.fit(v.co + v.normal * cap_off(dist[v]))
    bm.normal_update()
    cap_faces = list(bm.faces)
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
            lp[uvl].uv = (u, 0.0)
            lp[fl].uv = (0.0, 1.0)
    dl = bm.verts.layers.deform.active

    # ---------------------------------------------------------------- roots
    tris = []
    for f in cap_faces:
        vs = [v.co for v in f.verts]
        dd = sum(dist[v] for v in f.verts) / len(f.verts)
        for i in range(1, len(vs) - 1):
            a, b, c = vs[0], vs[i], vs[i + 1]
            tris.append((a, b, c, (b - a).cross(c - a).length * 0.5, dd))
    cum, acc = [], 0.0
    for t in tris:
        acc += t[3]
        cum.append(acc)

    def sample():
        x = rnd.random() * acc
        a, b, c, _, dd = tris[min(bisect.bisect_left(cum, x), len(tris) - 1)]
        u, v = rnd.random(), rnd.random()
        if u + v > 1:
            u, v = 1 - u, 1 - v
        return a + (b - a) * u + (c - a) * v, dd

    cand = [sample() for _ in range(12000)]

    def poisson(r, pts, taken):
        grid = {}
        for p in taken:
            grid.setdefault((int(p.x // r), int(p.y // r), int(p.z // r)), []).append(p)
        out = []
        for p, dd in pts:
            k = (int(p.x // r), int(p.y // r), int(p.z // r))
            if any((o - p).length < r for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1)
                   for o in grid.get((k[0] + dx, k[1] + dy, k[2] + dz), ())):
                continue
            grid.setdefault(k, []).append(p)
            out.append((p, dd))
        return out

    # the sides and the back stay a smooth short cut (the mass): locks only on the fringe - a few long bangs
    # rooted well back from the forehead hairline - and over the crown
    def lock_zone(p, dd):
        q = rel(p)
        if q.y < -0.05:
            return dd > 0.012 * K
        return q.z > 0.1 or (q.y < -0.03 and q.z > 0.085)
    rest = poisson(0.019 * K, [c for c in cand if c[1] >= 0.004 * K and lock_zone(*c)], [])
    roots = [p for p, _ in rest]

    # ---------------------------------------------------------------- locks
    nverts = len(bm.verts)
    hatk = {}
    nlocks = 0
    RING = 8
    centre = hc + Vector((0.0, 0.005, 0.075)) * K
    vol_n = {}

    def lock_vert(p, n, sl):
        v = bm.verts.new(p)
        v[dl].clear()
        loc, _, fi = near(p)
        for g, x in _groups(src, dl_src, fi, loc).items():
            v[dl][g] = x
        hatk[v] = 1.0 if hat.under(p) else 0.0
        vol_n[v] = n
        return v

    for p0 in roots:
        loc, n, fi = near(p0)
        q = rel(loc)
        top = _ss(0.085, 0.125, q.z)
        frontk = _ss(-0.035, -0.075, q.y)
        back = _ss(0.0, 0.05, q.y)
        low = 1.0 - _ss(0.02, 0.07, q.z)
        ear = _ss(0.05, 0.07, abs(q.x)) * (1.0 - _ss(0.06, 0.09, q.z)) * (1.0 - back)
        nz = noise.noise(q * 50.0) * 0.5 + 0.5
        L = 0.02 + 0.016 * top
        L = L + (0.05 - L) * frontk
        L *= 1.0 - 0.3 * ear - 0.25 * low * back
        L *= (0.85 + 0.3 * nz) * rnd.uniform(0.88, 1.12)
        L *= K
        w0 = (0.022 + 0.006 * rnd.random()) * K * (0.75 + 0.25 * _ss(0.01, 0.03, L / K))
        w0 *= 1.0 + 0.3 * frontk
        t0 = 0.003 * K * (0.8 + 0.2 * top)
        lift = (0.0005 + 0.0012 * top) * K * rnd.uniform(0.7, 1.3)
        yaw = rnd.uniform(-0.28, 0.28) * (1.0 - 0.6 * frontk)
        curl = rnd.uniform(-0.35, 0.35) * (1.0 - 0.5 * frontk)
        nseg = 5
        pts, nrm = [], []
        cur = loc
        d = None
        dd0 = cap_off(0.02 * K)
        for k in range(nseg + 1):
            t = k / nseg
            sl, sn, _ = near(cur)
            if k > 0 and ((sl - cur).length > 0.02 * K or not _grow_ok(rel(sl))):
                break
            h = dd0 * (1.0 - t) * 0.8 + 0.0012 * K + lift * math.sin(math.pi * min(t, 0.85)) + t0 * 0.5 * (1.0 - t)
            pts.append(sl + sn * h)
            nrm.append(sn)
            fd = flow(sl, sn)
            fd = Matrix.Rotation(yaw + curl * t, 3, sn) @ fd
            d = fd if d is None else (d * 0.5 + fd * 0.5)
            d -= sn * d.dot(sn)
            d.normalize()
            cur = sl + d * (L / nseg)
        if len(pts) < 3:
            continue
        for i in range(len(pts)):
            pts[i] = hat.fit(pts[i])
            sl, sn, _ = near(pts[i])
            if (pts[i] - sl).dot(sn) < 0.0011 * K:
                pts[i] = sl + sn * 0.0011 * K
        m = len(pts) - 1
        rings = []
        for i in range(m):
            t = i / m
            dirv = (pts[min(i + 1, m)] - pts[max(i - 1, 0)]).normalized()
            sn = nrm[i]
            side = sn.cross(dirv).normalized()
            up = dirv.cross(side).normalized()
            hw = 0.5 * w0 * max(0.0, 1.0 - t ** 1.6) ** 0.7 * (0.8 + 0.2 * _ss(0.0, 0.3, t))
            ht = 0.5 * t0 * max(0.0, 1.0 - t ** 1.6) ** 0.6
            ring = []
            for j in range(RING):
                a = 2.0 * math.pi * j / RING
                # flatter underneath (lies on the head), rounder on top
                off = side * math.cos(a) * hw + up * math.sin(a) * ht * (1.0 if math.sin(a) > 0 else 0.5)
                rn = (side * math.cos(a) / max(hw, 1e-5) + up * math.sin(a) / max(ht, 1e-5)).normalized()
                ring.append((lock_vert(pts[i] + off, rn, pts[i]), j / RING, t))
            rings.append(ring)
        tip = lock_vert(pts[m], (pts[m] - pts[m - 1]).normalized(), pts[m])
        for i in range(len(rings) - 1):
            for j in range(RING):
                a, ua, ta = rings[i][j]
                b, ub, tb = rings[i][(j + 1) % RING]
                c, uc, tc = rings[i + 1][(j + 1) % RING]
                e, ue, te = rings[i + 1][j]
                f = bm.faces.new((a, b, c, e))
                for lp, (u, t) in zip(f.loops, ((ua, ta), (ub if j + 1 < RING else 1.0, tb), (uc if j + 1 < RING else 1.0, tc), (ue, te))):
                    lp[uvl].uv = (u, t)
                    lp[fl].uv = (t ** 1.5, 0.0)
        last = rings[-1]
        for j in range(RING):
            a, ua, ta = last[j]
            b, ub, tb = last[(j + 1) % RING]
            f = bm.faces.new((a, b, tip))
            for lp, (u, t) in zip(f.loops, ((ua, ta), (ub if j + 1 < RING else 1.0, tb), ((ua + 0.5 / RING), 1.0))):
                lp[uvl].uv = (u, t)
                lp[fl].uv = (t ** 1.5, 0.0)
        first = rings[0]
        f = bm.faces.new([first[j][0] for j in reversed(range(RING))])
        for lp in f.loops:
            lp[uvl].uv = (0.5, 0.0)
            lp[fl].uv = (0.0, 0.0)
        nlocks += 1
    bm.verts.index_update()
    hatk = {v.index: k for v, k in hatk.items()}
    vol_n = {v.index: n for v, n in vol_n.items()}
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
    att = me.attributes.new("cb", "FLOAT", "POINT")
    kv = [0.0] * len(me.vertices)
    for i, k in hatk.items():
        kv[i] = k
    for v in me.vertices:
        if v.index not in hatk:
            kv[v.index] = 1.0 if hat.under(v.co) else 0.0
    att.data.foreach_set("value", kv)
    # normals: the mass keeps its own; each lock blends its round section with the head's volume, so the
    # locks read as soft ridges on one shape rather than separate tubes
    nb = []
    for v in me.vertices:
        if v.index not in vol_n:
            nb.append(v.normal.copy())
        else:
            radial = (v.co - centre).normalized()
            nb.append((vol_n[v.index] * 0.2 + radial * 0.8).normalized())
    me.normals_split_custom_set_from_vertices(nb)
    print("HAIR mass verts", nverts, "locks", nlocks, "tris", sum(len(p.vertices) - 2 for p in me.polygons), "K %.3f" % K)
    return ob
