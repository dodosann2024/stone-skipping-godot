"""Arm / body clearance: is any part of an arm inside the torso (or the other arm)?

The torso is a swept cross-section along a spine polyline built only from bone *positions* (crotch, pelvis,
spine_01..03, neck base), so Godot can rebuild the same volume from the exported skeleton (dev/selftest.gd).
Each slice's outline is measured once from the rest mesh (body + tank top + vest + shorts) as a radius per
angle in the slice plane (lateral = hips / shoulders line, forward = lateral x spine). An arm point's
clearance is its distance to that outline minus the limb's radius there.
"""
import math, json
from mathutils import Vector

NODES = ["crotch", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01"]
LAT_W = [0.0, 0.0, 0.0, 0.5, 1.0, 1.0]          # 0 = hip line, 1 = shoulder line
ANG = 32
BINS = 14
TORSO_BONES = {"pelvis", "spine_01", "spine_02", "spine_03"}
CROTCH_DROP = 0.09


def nodes_from(P):
    """P: bone name -> position (rest or posed). Returns spine node positions and lateral axes."""
    hip = (P["thigh_l"] + P["thigh_r"]) * 0.5
    up = (P["spine_01"] - P["pelvis"]).normalized()
    pts = [hip - up * CROTCH_DROP] + [P[n] for n in NODES[1:]]
    lh = (P["thigh_l"] - P["thigh_r"]).normalized()
    ls = (P["clavicle_l"] - P["clavicle_r"]).normalized()
    lats = [(lh * (1 - w) + ls * w).normalized() for w in LAT_W]
    return pts, lats


def _seglens(pts):
    return [(pts[i + 1] - pts[i]).length for i in range(len(pts) - 1)]


def frame_at(pts, lats, s):
    """s in [0, 1] along the polyline -> (centre, tangent, lateral, forward)"""
    L = _seglens(pts)
    tot = sum(L)
    d = min(max(s, 0.0), 1.0) * tot
    i = 0
    while i < len(L) - 1 and d > L[i]:
        d -= L[i]
        i += 1
    u = d / L[i] if L[i] > 0 else 0.0
    c = pts[i].lerp(pts[i + 1], u)
    t = (pts[i + 1] - pts[i]).normalized()
    lat = lats[i].lerp(lats[i + 1], u)
    lat = (lat - t * lat.dot(t)).normalized()
    fwd = lat.cross(t).normalized()
    return c, t, lat, fwd


def project(pts, p):
    """nearest polyline parameter s (0..1) and the signed overshoot beyond the ends (m)"""
    L = _seglens(pts)
    tot = sum(L)
    best = (1e9, 0.0, 0.0)
    acc = 0.0
    for i in range(len(L)):
        a, b = pts[i], pts[i + 1]
        ab = b - a
        u = (p - a).dot(ab) / max(ab.length_squared, 1e-9)
        uc = min(max(u, 0.0), 1.0)
        q = a + ab * uc
        dist = (p - q).length
        over = 0.0
        if i == 0 and u < 0:
            over = -u * ab.length
        if i == len(L) - 1 and u > 1:
            over = (u - 1) * ab.length
        if dist < best[0]:
            best = (dist, (acc + uc * L[i]) / tot, over)
        acc += L[i]
    return best[1], best[2]


def measure(rest_pos, verts):
    """verts: rest-space torso vertices -> profile {bins: [[r per angle]], ...}"""
    pts, lats = nodes_from(rest_pos)
    R = [[0.0] * ANG for _ in range(BINS)]
    for v in verts:
        s, over = project(pts, v)
        if over > 0.0:
            continue
        c, t, lat, fwd = frame_at(pts, lats, s)
        q = v - c
        x, y = q.dot(lat), q.dot(fwd)
        r = math.hypot(x, y)
        a = (math.atan2(y, x) / (2 * math.pi)) % 1.0
        b = min(int(s * BINS), BINS - 1)
        k = int(round(a * ANG)) % ANG
        for kk in (k - 1, k, k + 1):
            R[b][kk % ANG] = max(R[b][kk % ANG], r * math.cos(2 * math.pi / ANG * (kk - a * ANG)))
    # fill empty angles from neighbours, smooth a little
    for b in range(BINS):
        for _ in range(ANG):
            for k in range(ANG):
                if R[b][k] <= 0.0:
                    R[b][k] = max(R[b][(k - 1) % ANG], R[b][(k + 1) % ANG]) * 0.98
    return {"bins": [[round(r, 4) for r in row] for row in R], "angles": ANG, "crotch_drop": CROTCH_DROP,
            "lat_w": LAT_W}


def _radius(prof, s, ang):
    R = prof["bins"]
    nb = len(R)
    x = min(max(s * nb - 0.5, 0.0), nb - 1.0)
    b0 = int(x)
    b1 = min(b0 + 1, nb - 1)
    fb = x - b0
    n = prof["angles"]
    y = (ang / (2 * math.pi)) % 1.0 * n
    k0 = int(y) % n
    k1 = (k0 + 1) % n
    fk = y - int(y)
    r0 = R[b0][k0] * (1 - fk) + R[b0][k1] * fk
    r1 = R[b1][k0] * (1 - fk) + R[b1][k1] * fk
    return r0 * (1 - fb) + r1 * fb


def torso_dist(prof, pts, lats, p):
    """approximate distance from p to the torso surface (negative inside)"""
    s, over = project(pts, p)
    c, t, lat, fwd = frame_at(pts, lats, s)
    q = p - c
    x, y = q.dot(lat), q.dot(fwd)
    rho = math.hypot(x, y)
    a = math.atan2(y, x)
    r = _radius(prof, s, a)
    e = 0.05
    dr = (_radius(prof, s, a + e) - _radius(prof, s, a - e)) / (2 * e)
    d = (rho - r) * r / math.sqrt(r * r + dr * dr)
    if over > 0.0:
        d = math.hypot(max(d, 0.0), over) if d > 0 else over
    return d


# limb samples: (from bone, to bone, t, radius key)
ARM_SAMPLES = [("upperarm", "lowerarm", 0.55, "ua"), ("upperarm", "lowerarm", 0.8, "ua"), ("lowerarm", None, 0.0, "el"),
               ("lowerarm", "hand", 0.25, "fa"), ("lowerarm", "hand", 0.5, "fa"), ("lowerarm", "hand", 0.75, "fa"),
               ("hand", None, 0.0, "wr"), ("hand", "middle_01", 0.6, "hd"), ("middle_01", "middle_03", 1.0, "fi")]
# Concept A soft limbs are thinner than the MH teen; keep radii honest so throw clearance passes.
LIMB_R = {"ua": 0.028, "el": 0.026, "fa": 0.024, "wr": 0.020, "hd": 0.018, "fi": 0.010}
LEG_R = (0.07, 0.045)                            # thigh (shorts), calf
LABEL = {"ua": "upper arm", "el": "elbow", "fa": "forearm", "wr": "wrist", "hd": "hand", "fi": "fingers"}


def arm_points(P, s):
    out = []
    for a, b, t, key in ARM_SAMPLES:
        pa = P[a + "_" + s]
        p = pa if b is None else pa.lerp(P[b + "_" + s], t)
        out.append((p, key))
    return out


def _seg_dist(p1, q1, p2, q2):
    d1, d2, r = q1 - p1, q2 - p2, p1 - p2
    a, e, f = d1.dot(d1), d2.dot(d2), d2.dot(r)
    if a < 1e-9 and e < 1e-9:
        return r.length
    if a < 1e-9:
        return (p1 - (p2 + d2 * min(max(f / e, 0.0), 1.0))).length
    c = d1.dot(r)
    b = d1.dot(d2)
    den = a * e - b * b
    s = min(max((b * f - c * e) / den, 0.0), 1.0) if den > 1e-9 else 0.0
    t = (b * s + f) / e if e > 1e-9 else 0.0
    if t < 0:
        t, s = 0.0, min(max(-c / a, 0.0), 1.0)
    elif t > 1:
        t, s = 1.0, min(max((b - c) / a, 0.0), 1.0)
    return ((p1 + d1 * s) - (p2 + d2 * t)).length


def clearance(prof, P, radii=LIMB_R):
    """-> {"r": (min elbow/forearm/wrist/hand clearance, label), "r_ua": upper arm, "l", "l_ua",
    "arms": (min arm-arm gap, label)}"""
    pts, lats = nodes_from(P)
    res = {}
    for s in "lr":
        best = (1e9, "")
        best_ua = (1e9, "")
        for p, key in arm_points(P, s):
            d = torso_dist(prof, pts, lats, p) - radii[key]
            if key == "ua":
                best_ua = min(best_ua, (d, LABEL[key]))
            elif d < best[0]:
                best = (d, LABEL[key])
        res[s] = best
        res[s + "_ua"] = best_ua
    segs = {}
    for s in "lr":
        segs[s] = [(P["upperarm_" + s].lerp(P["lowerarm_" + s], 0.5), P["lowerarm_" + s], 0.037),
                   (P["lowerarm_" + s], P["hand_" + s], 0.031), (P["hand_" + s], P["middle_03_" + s], 0.022)]
    best = (1e9, "")
    for i, (a1, b1, r1) in enumerate(segs["r"]):
        for j, (a2, b2, r2) in enumerate(segs["l"]):
            d = _seg_dist(a1, b1, a2, b2) - r1 - r2
            if d < best[0]:
                best = (d, "R%d-L%d" % (i, j))
    res["arms"] = best
    best = (1e9, "")
    for s in "lr":
        for p, key in arm_points(P, s):
            if key == "ua":
                continue
            for leg in "lr":
                for a, b, r in (("thigh_", "calf_", LEG_R[0]), ("calf_", "foot_", LEG_R[1])):
                    d = _seg_dist(p, p, P[a + leg], P[b + leg]) - r - radii[key]
                    if d < best[0]:
                        best = (d, "%s %s-%s%s" % (s.upper(), LABEL[key], a, leg))
    res["legs"] = best
    return res


BONES = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "thigh_l", "thigh_r", "clavicle_l", "clavicle_r",
         "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r", "middle_01_l", "middle_01_r",
         "middle_03_l", "middle_03_r", "calf_l", "calf_r", "foot_l", "foot_r"]


def positions(M):
    return {n: M[n].translation.copy() for n in BONES}


def measure_rig(rig):
    """profile from the rest meshes in the blend (call before the parts are joined)"""
    import bpy
    rest = {n: rig.head[n].copy() for n in BONES}
    verts = []
    for name in ("Body", "Tank", "Vest", "Shorts"):
        ob = bpy.data.objects.get(name)
        if ob is None:
            continue
        gi = {g.index: g.name for g in ob.vertex_groups}
        mw = ob.matrix_world
        for v in ob.data.vertices:
            if not v.groups:
                continue
            g = max(v.groups, key=lambda x: x.weight)
            if gi.get(g.group) in TORSO_BONES and g.weight > 0.5:
                verts.append(mw @ v.co)
    prof = measure(rest, verts)
    # vest / shorts solidify outward by 3 mm
    prof["bins"] = [[round(r + 0.004, 4) for r in row] for row in prof["bins"]]
    prof["limb_r"] = LIMB_R
    return prof


def save(prof, path):
    json.dump(prof, open(path, "w"))
