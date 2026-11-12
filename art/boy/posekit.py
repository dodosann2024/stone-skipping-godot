"""Pose solver for the game_engine skeleton (Blender space: -Y forward, +X = the boy's left, Z up).

A pose is a dict of high-level parameters; solve() turns it into armature-space bone matrices
(two-bone IK for legs and arms with hinge frames, heel/ball roll for the feet), key() writes them
as keyframes. Missing parameters fall back to DEFAULT.
"""
import bpy, math
from mathutils import Vector, Matrix, Quaternion, Euler

GROUND = -0.012          # sole bottom of the flip-flops
FINGERS = ["thumb", "index", "middle", "ring", "pinky"]
SHRUG = 0.20             # collar bone lift (rad) with the arm fully overhead


def V(*a):
    return Vector(a)


def rot(p=0.0, r=0.0, y=0.0):
    """pitch (+ = lean forward, about +X), roll (+ = top towards +X), yaw (+ = turn left)"""
    return (Matrix.Rotation(y, 3, "Z") @ Matrix.Rotation(r, 3, "Y") @ Matrix.Rotation(p, 3, "X"))


class Rig:
    def __init__(self, arm):
        self.arm = arm
        self.rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in arm.data.bones}
        self.order = [b.name for b in arm.data.bones]  # parents come first
        self.head = {n: m.translation.copy() for n, m in self.rest.items()}
        self.R = {n: m.to_3x3().normalized() for n, m in self.rest.items()}
        self.tail = {b.name: b.tail_local.copy() for b in arm.data.bones}
        H = self.head
        for s in "lr":
            self.__dict__["L1" + s] = (H["calf_" + s] - H["thigh_" + s]).length
            self.__dict__["L2" + s] = (H["foot_" + s] - H["calf_" + s]).length
            self.__dict__["A1" + s] = (H["lowerarm_" + s] - H["upperarm_" + s]).length
            self.__dict__["A2" + s] = (H["hand_" + s] - H["lowerarm_" + s]).length
        # rest foot geometry
        self.ankle0 = {s: H["foot_" + s].copy() for s in "lr"}
        self.ball0 = {s: H["ball_" + s].copy() for s in "lr"}
        self.heel0 = {s: V(H["foot_" + s].x, H["foot_" + s].y + 0.035, GROUND) for s in "lr"}
        self.ballg0 = {s: V(H["ball_" + s].x, H["ball_" + s].y, GROUND) for s in "lr"}
        # hinge frames at rest
        self.leg_rest = {}
        self.arm_rest = {}
        for s in "lr":
            hip, kn, an = H["thigh_" + s], H["calf_" + s], H["foot_" + s]
            hinge = _hinge(an - hip, kn, hip, an, V(0, -1, 0))
            self.leg_rest[s] = (_frame(hinge, kn - hip), _frame(hinge, an - kn))
            sh, el, wr = H["upperarm_" + s], H["lowerarm_" + s], H["hand_" + s]
            hinge = (el - sh).cross(wr - el).normalized()
            self.arm_rest[s] = (_frame(hinge, el - sh), _frame(hinge, wr - el))

    def stand_ankle(self, s):
        """flat-foot ankle position for the natural stance (feet a bit closer than the A-pose)"""
        a = self.ankle0[s].copy()
        # Concept A short stance: feet under the narrower hips
        a.x = 0.07 if s == "l" else -0.07
        a.y = 0.0
        return a


def _smooth(x, a, b):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def _frame(x, d):
    y = d.normalized()
    x = (x - y * x.dot(y)).normalized()
    z = x.cross(y)
    return Matrix((x, y, z)).transposed()


def _hinge(reach, mid, a, b, fallback):
    """hinge axis of a two-bone chain: perpendicular to the reach line and the joint offset"""
    t = reach.normalized()
    off = mid - (a + t * (mid - a).dot(t))
    if off.length < 1e-4:
        off = fallback - t * fallback.dot(t)
    return t.cross(off.normalized()).normalized()


def two_bone(a, target, l1, l2, pole):
    """returns (joint, end) for a two-bone chain from a towards target, bending towards pole"""
    d = target - a
    dist = d.length
    over = max(0.0, dist - (l1 + l2) * 0.9995)
    dist = min(max(dist, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.9995)
    t = d.normalized()
    x = (dist * dist + l1 * l1 - l2 * l2) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - x * x, 0.0))
    p = (pole - t * pole.dot(t))
    if p.length < 1e-6:
        p = t.orthogonal()
    p.normalize()
    j = a + t * x + p * h
    return j, a + t * dist, over


DEFAULT = {
    "pel": V(0, 0, 0), "prot": (0.0, 0.0, 0.0),
    "sp": (0.0, 0.0, 0.0), "neck": (0.0, 0.0, 0.0), "head": (0.0, 0.0, 0.0),
    "clav_l": (0.0, 0.0, 0.0), "clav_r": (0.0, 0.0, 0.0),
    # hands in rest armature space (Concept A ~4-heads: shoulders ~0.73, hands hang near hips)
    "hl": V(0.20, 0.03, 0.50), "hr": V(-0.20, 0.03, 0.50),
    "el": V(0.35, 1.0, 0.0), "er": V(-0.35, 1.0, 0.0), "hlw": 0.0, "hrw": 0.0,
    "wl": (0.0, 0.0, 0.0), "wr": (0.0, 0.0, 0.0),
    "gl": 0.25, "gr": 0.25,
    # feet: flat ankle position (root space), yaw, pitch (+ toes up, heel pivot / - heel up, ball pivot)
    "fl": None, "fr": None, "yl": 0.07, "yr": -0.07, "pl": 0.0, "pr": 0.0, "tl": 0.0, "tr": 0.0,
    "kl": None, "kr": None,
}


def pose(**kw):
    p = dict(DEFAULT)
    p.update(kw)
    return p


def lerp_pose(a, b, k):
    o = {}
    for key in a:
        va, vb = a[key], b.get(key, a[key])
        o[key] = _lerp(va, vb, k)
    return o


def _lerp(va, vb, k):
    if va is None or vb is None:
        return va if k < 0.5 else vb
    if isinstance(va, Vector):
        return va.lerp(vb, k)
    if isinstance(va, tuple):
        return tuple(x + (y - x) * k for x, y in zip(va, vb))
    return va + (vb - va) * k


def catmull(keys, t):
    """keys: [(time, pose)], smooth through key poses (Catmull-Rom on every parameter)"""
    if t <= keys[0][0]:
        return dict(keys[0][1])
    if t >= keys[-1][0]:
        return dict(keys[-1][1])
    i = 0
    while keys[i + 1][0] < t:
        i += 1
    t0, p0 = keys[i]
    t1, p1 = keys[i + 1]
    pm = keys[i - 1][1] if i > 0 else p0
    pn = keys[i + 2][1] if i + 2 < len(keys) else p1
    u = (t - t0) / (t1 - t0)
    o = {}
    for key in p0:
        a, b, c, d = pm[key], p0[key], p1[key], pn[key]
        o[key] = _cr(a, b, c, d, u)
    return o


def _cr(a, b, c, d, u):
    if b is None or c is None:
        return b if u < 0.5 else c
    if a is None:
        a = b
    if d is None:
        d = c
    if isinstance(b, Vector):
        return Vector(tuple(_cr1(a[i], b[i], c[i], d[i], u) for i in range(3)))
    if isinstance(b, tuple):
        return tuple(_cr1(a[i], b[i], c[i], d[i], u) for i in range(len(b)))
    return _cr1(a, b, c, d, u)


def _cr1(a, b, c, d, u):
    # centripetal-ish damping: tangents scaled down to avoid overshoot between holds
    m1 = (c - a) * 0.5 * 0.85
    m2 = (d - b) * 0.5 * 0.85
    u2, u3 = u * u, u * u * u
    return (2 * u3 - 3 * u2 + 1) * b + (u3 - 2 * u2 + u) * m1 + (-2 * u3 + 3 * u2) * c + (u3 - u2) * m2


def solve(rig, p):
    """pose dict -> armature-space 4x4 matrices for every bone"""
    H, R = rig.head, rig.R
    M = {}

    def fk(name, G=None, at=None):
        par = rig.parent[name]
        rel = rig.rest[par].inverted() @ rig.rest[name] if par else rig.rest[name]
        base = (M[par] @ rel) if par else rel
        if G is not None:
            m3 = G @ base.to_3x3()
            base = Matrix.Translation(base.translation) @ m3.to_4x4()
        if at is not None:
            base = Matrix.Translation(at) @ base.to_3x3().to_4x4()
        M[name] = base
        return base

    def local_g(name, e):
        """rotation e (pitch, roll, yaw in character axes) applied in the parent's current frame"""
        par = rig.parent[name]
        parR = (M[par].to_3x3() @ R[par].inverted()) if par else Matrix.Identity(3)
        return parR @ rot(*e) @ parR.inverted()

    M["Root"] = rig.rest["Root"].copy()
    # pelvis
    pr = rot(*p["prot"])
    M["pelvis"] = Matrix.Translation(H["pelvis"] + p["pel"]) @ (pr @ R["pelvis"]).to_4x4()
    sp = p["sp"]
    for b, w in (("spine_01", 0.3), ("spine_02", 0.3), ("spine_03", 0.4)):
        fk(b, local_g(b, (sp[0] * w, sp[1] * w, sp[2] * w)))
    fk("neck_01", local_g("neck_01", p["neck"]))
    fk("head", local_g("head", p["head"]))
    chest = M["spine_03"] @ rig.rest["spine_03"].inverted()
    over = 0.0
    down = chest.to_3x3() @ V(0, 0, -1)
    for s in "lr":
        ce = p["clav_" + s]
        fk("clavicle_" + s, local_g("clavicle_" + s, ce))
        # arm IK in chest space
        sh = (M["clavicle_" + s] @ (rig.rest["clavicle_" + s].inverted() @ rig.rest["upperarm_" + s])).translation
        # hand targets live in the chest frame; hXw blends towards plain root space
        tgt = (chest @ p["h" + s]).lerp(p["h" + s], p["h" + s + "w"])
        pole = chest.to_3x3() @ p["e" + s]
        el, wr, o = two_bone(sh, tgt, rig.__dict__["A1" + s], rig.__dict__["A2" + s], pole)
        # the collar bone follows a raised arm (scapulohumeral rhythm, kept subtle), then re-solve
        lift = SHRUG * _smooth((el - sh).angle(down, 0.0), math.radians(75), math.radians(165))
        if lift > 1e-4:
            fk("clavicle_" + s, local_g("clavicle_" + s, (ce[0], ce[1] + (lift if s == "r" else -lift), ce[2])))
            sh = (M["clavicle_" + s] @ (rig.rest["clavicle_" + s].inverted() @ rig.rest["upperarm_" + s])).translation
            el, wr, o = two_bone(sh, tgt, rig.__dict__["A1" + s], rig.__dict__["A2" + s], pole)
        hinge = (el - sh).cross(wr - el)
        if hinge.length < 1e-5:
            hinge = (wr - sh).cross(pole)
        hinge.normalize()
        fu, fl_ = rig.arm_rest[s]
        Gu = _frame(hinge, el - sh) @ fu.inverted()
        Gl = _frame(hinge, wr - el) @ fl_.inverted()
        M["upperarm_" + s] = Matrix.Translation(sh) @ (Gu @ R["upperarm_" + s]).to_4x4()
        M["lowerarm_" + s] = Matrix.Translation(el) @ (Gl @ R["lowerarm_" + s]).to_4x4()
        dn = "deltoid_" + s
        if dn in R:
            # helper half way between the arm as the collar bone carries it and the actual arm
            qa = (M["clavicle_" + s].to_3x3() @ R["clavicle_" + s].inverted() @ R["upperarm_" + s]).to_quaternion()
            qb = (Gu @ R["upperarm_" + s]).to_quaternion()
            if qa.dot(qb) < 0:
                qb.negate()
            q = qa.slerp(qb, 0.5).to_matrix() @ R["upperarm_" + s].inverted() @ R[dn]
            M[dn] = Matrix.Translation(sh) @ q.to_4x4()
        fk("hand_" + s, local_g("hand_" + s, p["w" + s]))
        g = p["g" + s]
        for f in FINGERS:
            for j in (1, 2, 3):
                n = "%s_%02d_%s" % (f, j, s)
                if f == "thumb":
                    a = g * (0.25 if j == 1 else 0.5)
                else:
                    a = g * (1.1 if j == 1 else 1.3 if j == 2 else 0.9)
                # curl around the bone's own X axis (mirrored roll -> same sign on both sides)
                par = rig.parent[n]
                rel = rig.rest[par].inverted() @ rig.rest[n]
                M[n] = M[par] @ rel @ Matrix.Rotation(a, 4, "X")
    for s in "lr":
        hip = (M["pelvis"] @ (rig.rest["pelvis"].inverted() @ rig.rest["thigh_" + s])).translation
        flat = p["f" + s] if p["f" + s] is not None else rig.stand_ankle(s)
        yaw, pitch = p["y" + s], p["p" + s]
        G = rot(-pitch, 0.0, yaw)
        Rz = rot(0, 0, yaw)
        # pivot: heel when the toes are up; the ball joint itself when the heel is up, so the flat toes
        # hinge in place instead of sliding forward as the heel rises
        a0 = rig.ankle0[s]
        if pitch >= 0:
            piv0 = rig.heel0[s]
        else:
            piv0 = rig.ball0[s]
        piv = flat + Rz @ (piv0 - a0)
        ankle = piv + G @ (a0 - piv0)
        kp = p["k" + s]
        if kp is None:
            kp = (Rz @ V(0, -1, 0)) + (pr @ V(0, -1, 0)) * 0.5
        kn, an, o = two_bone(hip, ankle, rig.__dict__["L1" + s], rig.__dict__["L2" + s], kp)
        over = max(over, o)
        hinge = _hinge(an - hip, kn, hip, an, kp)
        ft, fc = rig.leg_rest[s]
        Gt = _frame(hinge, kn - hip) @ ft.inverted()
        Gc = _frame(hinge, an - kn) @ fc.inverted()
        M["thigh_" + s] = Matrix.Translation(hip) @ (Gt @ R["thigh_" + s]).to_4x4()
        M["calf_" + s] = Matrix.Translation(kn) @ (Gc @ R["calf_" + s]).to_4x4()
        M["foot_" + s] = Matrix.Translation(an) @ (G @ R["foot_" + s]).to_4x4()
        ballp = (M["foot_" + s] @ (rig.rest["foot_" + s].inverted() @ rig.rest["ball_" + s])).translation
        # toes stay flat on the ground while the heel is up, otherwise follow the foot (+ toe bend)
        tg = rot(0, 0, yaw) if pitch < 0 else rot(-(pitch + p["t" + s]), 0, yaw)
        M["ball_" + s] = Matrix.Translation(ballp) @ (tg @ R["ball_" + s]).to_4x4()
    return M, over


def to_basis(rig, M):
    out = {}
    for n in rig.order:
        par = rig.parent[n]
        if n not in M:
            continue
        rel = rig.rest[par].inverted() @ rig.rest[n] if par else rig.rest[n]
        pm = M[par] if par else Matrix.Identity(4)
        out[n] = rel.inverted() @ pm.inverted() @ M[n]
    return out


def apply_pose(rig, p):
    M, over = solve(rig, p)
    B = to_basis(rig, M)
    for n, m in B.items():
        pb = rig.arm.pose.bones[n]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = m.to_quaternion()
        pb.location = m.translation if n == "pelvis" else Vector()
    return M, over


def bake(rig, name, fn, frames, fps=30, loop=False):
    """fn(t) -> pose; keys every frame (frames+1 keys for loops so the cycle closes exactly)"""
    arm = rig.arm
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    prev = {}
    worst = 0.0
    info = {"pelvis": [], "hand_r": [], "head": [], "foot_l": [], "foot_r": []}
    n = frames + 1
    for f in range(n):
        t = f / fps
        M, over = apply_pose(rig, fn(t))
        worst = max(worst, over)
        for k in info:
            info[k].append(tuple(M[k].translation))
        for b in rig.order:
            pb = arm.pose.bones[b]
            q = pb.rotation_quaternion.copy()
            if b in prev and prev[b].dot(q) < 0:
                q.negate()
                pb.rotation_quaternion = q
            prev[b] = q
            pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
            if b == "pelvis":
                pb.keyframe_insert("location", frame=f, group=b)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    if worst > 0.01:
        print("WARN %s: limb over-reach %.3f m" % (name, worst))
    arm.animation_data.action = None
    return act, info
