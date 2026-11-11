"""v17 clothes as fabric, not shrink-wrap: finer faces where the cloth folds, folds / drape / hems / bindings
pushed out of the offset shell (never in, so no new skin poke-through), and per-vertex data for
shaders/cloth.gdshader:
  attribute "cb" -> COLOR.b  distance to the garment edge (0 at the edge .. 1 at 3 cm): hems, bindings, wear
  attribute "ca" -> COLOR.a  signed distance to a sewn seam (0.5 on the seam, 0 / 1 at -/+ 1.5 cm; signed
                             so it interpolates linearly across a triangle): seams and stitching
  attribute "cg" -> COLOR.g  fold crest (> 0.5) / valley (< 0.5)
  UV2.y                      like COLOR.a, a second seam (the shorts' centre front / back)
  UV2.x                      how free the hem is to sway (vest hem / opening, shorts leg openings)
Plus the shorts' drawstring.
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix, noise
from mathutils.interpolate import poly_3d_calc

HEM_D = 0.03
SEAM_D = 0.015


def ss(a, b, x):
    if a == b:
        return 1.0 if x >= b else 0.0
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def win(x, a, b, soft):
    """1 inside [a, b], soft shoulders"""
    return ss(a - soft, a, x) * (1.0 - ss(b, b + soft, x))


def pos(x):
    return max(0.0, x)


class Cloth:
    """fine: face centre -> subdivide; fold(co, n, ed) -> extra outward offset (m); seam(co) -> signed
    metres to the nearest seam; sway(co, ed) -> 0..1"""

    def __init__(self, fine=None, fold=None, seam=None, sway=None, line=None, seam2=None):
        self.fine, self._fold, self._seam, self._sway = fine, fold, seam, sway
        self._seam2 = seam2       # a second seam whose sign can't agree with the first one's (UV2.y)
        self._line = line         # line(co) -> metres to a sewn line that is not an edge (waistband)

    def subdivide(self, bm, bvh, src):
        if not self.fine:
            return
        faces = [f for f in bm.faces if self.fine(f.calc_center_median())]
        edges = list({e for f in faces for e in f.edges})
        res = bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)
        new = [g for g in res["geom_inner"] + res["geom_split"] if isinstance(g, bmesh.types.BMVert)]
        src.faces.ensure_lookup_table()
        dls = src.verts.layers.deform.active
        dl = bm.verts.layers.deform.active
        for v in set(new):
            loc, n, fi, d = bvh.find_nearest(v.co)
            if loc is None:
                continue
            v.co = loc
            fv = src.faces[fi].verts
            bw = poly_3d_calc([u.co for u in fv], loc)
            acc = {}
            for u, w in zip(fv, bw):
                for g, x in u[dls].items():
                    acc[g] = acc.get(g, 0.0) + w * x
            dv = v[dl]
            dv.clear()
            for g, x in acc.items():
                if x > 1e-4:
                    dv[g] = x
        bm.normal_update()

    def edge_distance(self, bm):
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
        if self._line:
            return {v: min(d, self._line(v.co), 1.0) for v, d in dist.items()}
        return {v: min(d, 1.0) for v, d in dist.items()}

    def fold(self, co, n, ed):
        return self._fold(co, n, ed) if self._fold else 0.0

    def cavity(self, bm, f):
        """attribute "cg" -> COLOR.g: 0.5 flat, < 0.5 in a fold's valley, > 0.5 on its crest (f: fold
        offsets by vertex index)"""
        cav = {}
        for v in bm.verts:
            nb = [f[e.other_vert(v).index] for e in v.link_edges]
            cav[v.index] = f[v.index] - sum(nb) / len(nb) if nb else 0.0
        cg = bm.verts.layers.float.new("cg")
        for v in bm.verts:
            nb = [cav[e.other_vert(v).index] for e in v.link_edges]
            c = 0.5 * cav[v.index] + 0.5 * (sum(nb) / len(nb) if nb else 0.0)
            v[cg] = min(max(0.5 + c / 0.0016, 0.0), 1.0)

    def store(self, bm, ed):
        cb = bm.verts.layers.float.new("cb")
        ca = bm.verts.layers.float.new("ca")
        for v in bm.verts:
            v[cb] = min(ed[v.index] / HEM_D, 1.0)
            v[ca] = min(max(0.5 + 0.5 * self._seam(v.co) / SEAM_D, 0.0), 1.0) if self._seam else 1.0
        while len(bm.loops.layers.uv) < 2:
            bm.loops.layers.uv.new()
        fl = bm.loops.layers.uv[1]
        for f in bm.faces:
            for lp in f.loops:
                s2 = min(max(0.5 + 0.5 * self._seam2(lp.vert.co) / SEAM_D, 0.0), 1.0) if self._seam2 else 1.0
                lp[fl].uv = (self._sway(lp.vert.co, ed[lp.vert.index]) if self._sway else 0.0, s2)


class Body:
    """slices of the body for seam lines: torso centre line and leg axes by height"""

    def __init__(self, body, J):
        self.J = J
        vs = [v.co.copy() for v in body.data.vertices]
        self.torso = {}
        self.legs = {1: {}, -1: {}}
        crotch = J["thigh_l"].z - 0.07
        for p in vs:
            k = int(round(p.z / 0.01))
            if abs(p.x) < 0.12 and p.z > crotch:
                self.torso.setdefault(k, []).append(p.y)
            if p.z < crotch + 0.03 and 0.0 < abs(p.x) < 0.15:
                s = 1 if p.x > 0 else -1
                self.legs[s].setdefault(k, []).append((p.x, p.y))
        raw = {k: (min(v) + max(v)) / 2 for k, v in self.torso.items()}
        # smoothed over +-3 cm so seams placed from it run straight
        self.torso = {k: sum(raw[j] for j in range(k - 3, k + 4) if j in raw) / sum(1 for j in range(k - 3, k + 4) if j in raw) for k in raw}
        legs = {}
        for s, d in self.legs.items():
            raw = {k: ((min(a for a, b in v) + max(a for a, b in v)) / 2, (min(b for a, b in v) + max(b for a, b in v)) / 2) for k, v in d.items()}
            sm = {}
            for k in raw:
                nb = [raw[j] for j in range(k - 3, k + 4) if j in raw]
                sm[k] = (sum(a for a, b in nb) / len(nb), sum(b for a, b in nb) / len(nb))
            legs[s] = sm
        self.legs = legs
        self.crotch = crotch

    def cy(self, z):
        k = int(math.floor(z / 0.01))
        f = z / 0.01 - k
        a, b = self.torso.get(k), self.torso.get(k + 1)
        if a is not None and b is not None:
            return a + (b - a) * f
        for dk in (0, 1, -1, 2, -2):
            if k + dk in self.torso:
                return self.torso[k + dk]
        return 0.0

    def leg(self, x, z):
        d = self.legs[1 if x > 0 else -1]
        k = int(math.floor(z / 0.01))
        f = z / 0.01 - k
        if k in d and k + 1 in d:
            a, b = d[k], d[k + 1]
            return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        for dk in (0, 1, -1, 2, -2, 3, -3):
            if k + dk in d:
                return d[k + dk]
        return (0.08 if x > 0 else -0.08, 0.0)


def _nz(co, f, amp):
    return noise.noise(co * f) * amp


def ridge(ph, co, f=7.0):
    """0..1 soft fold ridge across phase ph, fading in and out along its length (low-frequency
    noise) so folds read as separate creases rather than a regular corrugation"""
    r = (0.5 + 0.5 * math.sin(ph)) ** 2
    return r * ss(-0.35, 0.45, noise.noise(co * f + Vector((3.1, 7.7, 1.3))))


def drape(co, amp):
    """broad, gentle unevenness (cloth never lies perfectly flat), no small lumps"""
    return (0.5 + 0.5 * noise.noise(co * 5.0)) * amp


def side_seam(B, co, front_x):
    """signed distance to the side seam (front / back halves of the torso meet), pushed away from the
    middle of the front and back"""
    d = co.y - B.cy(co.z)
    return math.copysign(abs(d) + pos(front_x - abs(co.x)) * 2.0, d)


def armpit_side(J, B, co):
    """1 on the torso's sides just under the armholes, where the swinging upper arms pass within a few mm
    of the vest (selftest arm clearance): the vest keeps its v16 offset there, no folds, no raised binding"""
    neck, sh_x = J["neck_01"].z, J["upperarm_l"].x
    return (ss(0.065, 0.04, abs(co.y - B.cy(co.z))) * ss(sh_x - 0.11, sh_x - 0.08, abs(co.x))
            * win(co.z, neck - 0.26, neck - 0.13, 0.03))


def tank(J, B, under_vest):
    hip, neck = J["pelvis"].z, J["neck_01"].z

    def fold(co, n, ed):
        vis = 1.0 - under_vest(co)
        d = 0.0005 * (1.0 - ss(0.004, 0.009, ed)) * (1.0 if co.z < hip + 0.1 else 0.6)  # hem / binding
        # the strip showing in the vest's opening: soft vertical drape and a little bunching at the waist
        hang = ridge(co.x / 0.016 * math.pi + _nz(co, 6, 1.0), co) * 0.0016
        bunch = ridge((co.z - hip) / 0.011 * math.pi + _nz(co, 7, 1.2), co, 9.0) * 0.0016 * win(co.z, hip + 0.1, hip + 0.17, 0.02)
        return d + vis * (hang + bunch + drape(co, 0.0012))

    def seam(co):
        return side_seam(B, co, 0.07)

    return Cloth(fine=lambda c: abs(c.x) < 0.05 and c.y < 0 and c.z > hip + 0.08, fold=fold, seam=seam)


def vest(J, B):
    hip, neck = J["pelvis"].z, J["neck_01"].z
    sh_x = J["upperarm_l"].x

    def fold(co, n, ed):
        pit = armpit_side(J, B, co)
        d = 0.0011 * (1.0 - ss(0.005, 0.009, ed))                        # binding round every edge
        low = ss(neck - 0.17, hip + 0.1, co.z)                           # 0 chest .. 1 hem
        if co.y < 0:
            # the open fronts hang in a few soft vertical folds, deeper towards the hem
            ph = co.x / 0.021 * math.pi + _nz(co, 6, 1.2)
            d += ridge(ph, co) * (0.0015 + 0.0035 * low)
        else:
            # soft horizontal folds over the lower back
            d += ridge((co.z - hip) / 0.019 * math.pi + _nz(co, 6, 1.0), co) * 0.0026 * win(co.z, hip + 0.1, hip + 0.22, 0.03)
        # the sides under the armholes, where the arms swing past within a centimetre: flat apart from a
        # few shallow diagonal folds running from the armpit
        side = ss(0.035, 0.015, abs(co.y - B.cy(co.z))) * ss(sh_x - 0.12, sh_x - 0.08, abs(co.x)) * win(co.z, hip, neck - 0.13, 0.03)
        d *= (1.0 - 0.8 * side) * (1.0 - pit)
        arm = win(co.z, neck - 0.2, neck - 0.11, 0.03) * ss(sh_x - 0.11, sh_x - 0.06, abs(co.x))
        d += ridge((co.z * 0.8 + abs(co.x) * 0.7) / 0.012 * math.pi, co, 9.0) * 0.003 * arm * (1.0 - pit)
        # hangs a little off the shorts' waistband (less at the sides, where the arms swing past)
        d += 0.004 * (1.0 - ss(hip + 0.085, hip + 0.13, co.z)) * (1.0 - 0.6 * side)
        return d + drape(co, 0.0016) * (1.0 - 0.8 * side) * (1.0 - pit)

    def seam(co):
        return side_seam(B, co, 0.07)

    def sway(co, ed):
        # the hem and the lower front opening only: the armholes stay put next to the arms, and the
        # hem moves at half strength because it hangs just 4 mm over the shorts waistband
        return 0.5 * (1.0 - ss(0.0, 0.05, ed)) * (1.0 - ss(neck - 0.26, neck - 0.18, co.z))

    def fine(c):
        # (not the back of the armholes: finer faces there follow the hollow behind the armpit in raised-arm
        # poses closer than the tank top under them does)
        return (c.y < 0 and c.z < neck - 0.12) or (c.y >= 0 and c.z < hip + 0.24) or (neck - 0.22 < c.z < neck - 0.09 and abs(c.x) > sh_x - 0.12 and c.y < 0.015 and c.z > neck - 0.17)

    return Cloth(fine=fine, fold=fold, seam=seam, sway=sway)


def shorts(J, B, hem_z, top_z):
    def fold(co, n, ed):
        d = 0.0
        band = ss(top_z - 0.03, top_z - 0.024, co.z)
        d += 0.0012 * band                                               # waistband
        d += 0.0008 * (1.0 - ss(0.01, 0.016, ed)) * (1.0 - band)         # leg hems
        if co.z < B.crotch + 0.13 and abs(co.x) < 0.1:
            # folds fanning out from the crotch towards the hips, front and back
            u = abs(co.x) - (co.z - B.crotch) * 0.75
            d += ridge(u / 0.016 * math.pi + _nz(co, 6, 0.8), co) * 0.0034 * win(co.z, B.crotch - 0.02, B.crotch + 0.1, 0.03) * (1.0 - band) * ss(0.012, 0.03, abs(co.x))
        # gathered by the drawstring just under the waistband
        gz = win(co.z, top_z - 0.06, top_z - 0.03, 0.012)
        d += ridge(math.atan2(co.y - B.cy(co.z), co.x) * 26.0 + _nz(co, 8, 1.0), co, 12.0) * 0.0016 * gz
        if co.z < B.crotch:
            # drape round the leg openings, a few loose folds deepening to the hem
            cx, cy = B.leg(co.x, co.z)
            th = math.atan2(co.y - cy, co.x - cx)
            d += ridge(th * 4.0 + _nz(co, 6, 1.2), co, 5.0) * 0.005 * ss(hem_z + 0.13, hem_z, co.z)
        return d + drape(co, 0.0016) * (1.0 - band)

    def seam(co):
        if co.z > B.crotch + 0.01:
            return side_seam(B, co, 0.08)
        cx, cy = B.leg(co.x, co.z)
        return co.y - cy                                                  # outer side seam and inseam

    def centre(co):
        return co.x if co.z > B.crotch - 0.02 else math.copysign(1.0, co.x)  # centre front / back

    def sway(co, ed):
        return (1.0 - ss(0.0, 0.06, ed)) * (1.0 if co.z < B.crotch else 0.0)

    # the waistband's lower seam reads like a hem 11 mm from an edge (stitched there)
    def line(co):
        return abs(co.z - (top_z - 0.027)) + 0.011 if co.z > B.crotch + 0.05 else 1.0

    def fine(c):
        # not the bridge between the legs: new points there snap onto both thighs and fold over
        if abs(c.x) < 0.035 and c.z < B.crotch + 0.04:
            return False
        return c.z < B.crotch + 0.12 or c.z > top_z - 0.035

    return Cloth(fine=fine, fold=fold, seam=seam, sway=sway, line=line, seam2=centre)


def drawstring(rig, body, shorts_ob, top_z, mat, tube):
    """two cotton cords tied at the front of the waistband, hanging over it"""
    from mathutils.bvhtree import BVHTree
    sm = bmesh.new()
    sm.from_mesh(shorts_ob.data)
    bvh = BVHTree.FromBMesh(sm)
    sm.free()
    bm = bmesh.new()
    z0 = top_z - 0.012
    for sx in (1, -1):
        # the front surface of the waistband
        loc, n, fi, d = bvh.ray_cast(Vector((0.006 * sx, -0.5, z0)), Vector((0, 1, 0)))
        if loc is None:
            continue
        p0 = loc + Vector((0, -0.0025, 0))
        path = [p0, p0 + Vector((0.004 * sx, -0.003, -0.012)), p0 + Vector((0.009 * sx, -0.004, -0.03)),
                p0 + Vector((0.011 * sx, -0.0045, -0.05 if sx > 0 else -0.058))]
        tube(bm, path, 0.0017, 6)
        # knotted end
        e = path[-1]
        bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=0.0032,
                                  matrix=Matrix.Translation(e))
    me = bpy.data.meshes.new("Drawstring")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Drawstring", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = rig
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    # weights: the cords move with the waist (pelvis / lower spine), copied from the nearest shorts vertex
    sverts = shorts_ob.data.vertices
    groups = {g.index: g.name for g in shorts_ob.vertex_groups}
    from mathutils.kdtree import KDTree
    kd = KDTree(len(sverts))
    for v in sverts:
        kd.insert(v.co, v.index)
    kd.balance()
    for v in me.vertices:
        co, i, d = kd.find(Vector((v.co.x, v.co.y, max(v.co.z, z0))))
        for e in sverts[i].groups:
            g = ob.vertex_groups.get(groups[e.group]) or ob.vertex_groups.new(name=groups[e.group])
            g.add([v.index], e.weight, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return ob
