"""Animation clips for the v6 boy, written as functions of time over posekit poses.

Locomotion cycles are procedural (exact, slide-free stance phases); actions are key poses
interpolated with Catmull-Rom. Distances are in Blender units (the boy is 1.48 m tall here;
Godot scales him down).
"""
import math
from mathutils import Vector
from posekit import V, pose, catmull, lerp_pose, GROUND

TAU = math.pi * 2.0


def sm(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def minjerk(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * x * (10 - 15 * x + 6 * x * x)


def bump(x, c, w):
    return math.exp(-((x - c) / w) ** 2)


# ------------------------------------------------------------------ locomotion

class Gait:
    """one stride cycle: left heel strike at phase 0, right at 0.5"""

    def __init__(self, rig, period, stride, duty, run=False):
        self.rig = rig
        self.T = period
        self.S = stride
        self.duty = duty
        self.run = run
        self.v = stride / period
        # stance travel relative to the hip; running lands closer under the body
        travel = stride * duty
        self.y_strike = -travel * (0.42 if run else 0.5)
        self.y_off = self.y_strike + travel

    def foot(self, s, ph):
        """flat-ankle position, pitch for one foot at cycle phase ph"""
        u = (ph - (0.0 if s == "l" else 0.5)) % 1.0
        a0 = self.rig.stand_ankle(s)
        x = (0.085 if s == "l" else -0.085) * (0.85 if self.run else 1.0)
        D = self.duty
        if u < D:
            k = u / D
            y = self.y_strike + (self.y_off - self.y_strike) * k
            z = a0.z
            if self.run:
                pitch = 0.12 * (1 - sm(k / 0.25)) - 0.75 * sm((k - 0.45) / 0.55)
            else:
                pitch = 0.32 * (1 - sm(k / 0.2)) - 0.62 * sm((k - 0.62) / 0.38)
        else:
            k = (u - D) / (1 - D)
            m = minjerk(k)
            y = self.y_off + (self.y_strike - self.y_off) * m
            if self.run:
                # heel kicks up behind, knee drives forward, foot reaches out under the knee
                back = 0.16 * bump(k, 0.35, 0.22)
                y += back
                z = a0.z + 0.07 * math.sin(math.pi * k) + 0.20 * bump(k, 0.38, 0.22)
                pitch = -0.75 * (1 - sm(k / 0.35)) + 0.15 * sm((k - 0.6) / 0.4) - 0.5 * bump(k, 0.35, 0.18)
            else:
                z = a0.z + 0.045 * math.sin(math.pi * min(k * 1.15, 1.0)) ** 1.5 + 0.03 * bump(k, 0.25, 0.15)
                pitch = -0.62 * (1 - sm(k / 0.4)) + 0.38 * sm((k - 0.55) / 0.45)
        return V(x, y, z), pitch, u

    def pose(self, t):
        ph = (t / self.T) % 1.0
        run = self.run
        fl, pl, ul = self.foot("l", ph)
        fr, pr, ur = self.foot("r", ph)
        c = math.cos(TAU * ph)
        s2 = math.sin(TAU * ph)
        # vertical: walk is lowest just after each contact and highest at mid-stance (passing),
        # run is lowest at mid-stance and highest in the flight phase
        if run:
            pz = -0.075 + 0.032 * math.cos(TAU * 2 * (ph - 0.18 - 0.25))
        else:
            pz = -0.035 + 0.016 * math.cos(TAU * 2 * (ph - 0.27))
        yaw = -(0.07 if run else 0.11) * c
        roll = -(0.035 if run else 0.06) * math.sin(TAU * (ph - 0.04))
        px = (0.006 if run else 0.017) * math.sin(TAU * (ph - 0.06))
        lean = 0.17 if run else 0.04
        # counter-rotating chest, steady head
        sp_yaw = (0.30 if run else 0.24) * c
        sp_roll = -roll * 0.9
        chest_yaw = yaw + sp_yaw
        head_yaw = -chest_yaw * 0.85
        # arms swing contralaterally (left heel strike at phase 0 = right arm forward), slightly lagging
        A = 0.42 if run else 0.28
        out = {}
        for s, sgn in (("l", 1.0), ("r", -1.0)):
            ph_a = ph - (0.04 if not run else 0.03)
            swing = A * math.cos(TAU * ph_a) * (-1.0 if s == "l" else 1.0)
            # swing > 0: arm forward
            sh = V(0.153 * sgn, -0.014, 1.092)
            if run:
                ua, la = 0.22, 0.20
                elbow = 1.45 - 0.25 * swing
                ang = -0.2 + swing * 1.4
            else:
                ua, la = 0.195, 0.198
                elbow = 0.22 + 0.32 * max(swing, 0.0) / A
                ang = swing * 1.1
            # upper arm direction: down, rotated forward by ang, slightly out
            du = V(0.12 * sgn, -math.sin(ang), -math.cos(ang)).normalized()
            el = sh + du * 0.195
            fa = ang + elbow
            dl = V(0.05 * sgn if not run else -0.08 * sgn, -math.sin(fa), -math.cos(fa)).normalized()
            out["h" + s] = el + dl * 0.198
            out["e" + s] = V(0.3 * sgn, 1.0, -0.3)
        g = 0.55 if run else 0.3
        return pose(
            pel=V(px, 0.0, pz), prot=(lean, roll, yaw),
            sp=(0.04 if run else 0.0, sp_roll, sp_yaw), neck=(-0.1 if run else -0.02, 0, head_yaw * 0.4),
            head=(-lean * 0.6, -sp_roll * 0.5, head_yaw * 0.6),
            hl=out["hl"], hr=out["hr"], el=out["el"], er=out["er"], gl=g, gr=g,
            fl=fl, fr=fr, pl=pl, pr=pr, yl=0.06, yr=-0.06,
        )


def idle(rig):
    def fn(t):
        ph = t / 4.0
        br = math.sin(TAU * ph * 2)          # two breaths per loop
        sh = math.sin(TAU * ph)               # slow weight shift
        look = 0.25 * math.sin(TAU * ph) * sm((math.sin(TAU * ph) + 0.2) * 2)
        fl = rig.stand_ankle("l")
        fr = rig.stand_ankle("r")
        fl.y -= 0.02
        fr.y += 0.03
        fl.x += 0.01
        return pose(
            pel=V(0.012 * sh, 0.0, -0.012 - 0.004 * abs(sh)), prot=(0.0, -0.035 * sh, 0.03 * sh),
            sp=(-0.03 + 0.012 * br, 0.03 * sh, -0.02 * sh), neck=(0.0, 0.0, look * 0.4),
            head=(0.05 - 0.01 * br, -0.02 * sh, look * 0.6),
            hl=V(0.205, 0.01, 0.725 + 0.004 * br), hr=V(-0.205, 0.02, 0.725 + 0.004 * br),
            clav_l=(0, -0.01 * br, 0), clav_r=(0, 0.01 * br, 0),
            fl=fl, fr=fr, yl=0.16, yr=-0.12,
        )
    return fn


# ------------------------------------------------------------------ key-pose actions

def I(rig):
    """neutral standing pose (= idle at t=0, so actions start and end where idle is)"""
    return idle(rig)(0.0)


def P(base, **kw):
    p = dict(base)
    p.update(kw)
    return p


def keyed(keys):
    return lambda t: catmull(keys, t)


# throwing stances (left foot forward, right foot back), flat-ankle positions
ST_L, ST_R = V(0.075, -0.20, 0.055), V(-0.20, 0.15, 0.055)
CR_L, CR_R = V(0.11, -0.30, 0.055), V(-0.14, 0.34, 0.055)
T_CHARGE = 0.5      # charge part of the throw clips: seek 0..T_CHARGE by power
T_RELEASE = 0.65    # stone leaves the hand


def throw_stand(rig):
    i = I(rig)
    st = dict(fl=ST_L, fr=ST_R, yl=-0.25, yr=-0.7)
    ready = P(i, pel=V(-0.03, 0.0, -0.05), prot=(0.08, -0.02, -0.22), sp=(0.05, 0.0, -0.15),
              neck=(0.0, 0.0, 0.12), head=(0.05, 0.0, 0.2),
              hr=V(-0.21, -0.10, 0.76), er=V(-0.4, 0.8, -0.3), hl=V(0.21, -0.06, 0.78), gr=0.85, gl=0.3, **st)
    charge = P(ready, pel=V(-0.07, 0.07, -0.13), prot=(0.16, -0.08, -0.5), sp=(0.16, -0.06, -0.45),
               neck=(0.0, 0.0, 0.4), head=(0.05, 0.06, 0.45),
               hr=V(-0.30, 0.27, 0.80), er=V(-0.3, 0.5, -1.0), hl=V(0.22, -0.32, 0.93), el=V(0.6, 0.2, -0.6),
               pl=0.12, gr=0.95)
    whip = P(charge, pel=V(-0.02, 0.0, -0.12), prot=(0.2, -0.03, -0.1), sp=(0.18, 0.0, -0.1),
             hr=V(-0.34, 0.02, 0.70), pl=0.0, pr=-0.2, neck=(0, 0, 0.1), head=(0.0, 0.0, 0.1))
    release = P(charge, pel=V(0.02, -0.05, -0.10), prot=(0.24, 0.02, 0.24), sp=(0.2, 0.05, 0.25),
                neck=(-0.05, 0.0, -0.2), head=(0.0, 0.0, -0.25),
                hr=V(-0.30, -0.38, 0.52), hrw=1.0, er=V(-0.5, 0.5, -1.0), hl=V(0.30, 0.06, 0.84), el=V(0.6, 0.8, 0.0),
                pl=0.0, pr=-0.4, gr=0.4)
    follow = P(release, pel=V(0.04, -0.08, -0.09), prot=(0.3, 0.04, 0.5), sp=(0.3, 0.05, 0.35),
               neck=(-0.05, 0.0, -0.3), head=(-0.1, 0.0, -0.45),
               hr=V(0.10, -0.33, 0.60), er=V(-0.3, 1.0, -0.3), hl=V(0.27, 0.2, 0.78), pr=-0.9, gr=0.2)
    hold = P(follow, pel=V(0.03, -0.06, -0.06), prot=(0.14, 0.02, 0.4), sp=(0.1, 0.0, 0.2),
             neck=(0.0, 0.0, -0.3), head=(0.0, 0.0, -0.4), hr=V(-0.06, -0.2, 0.76), hrw=0.0, hl=V(0.22, 0.05, 0.76), pr=-0.7, gr=0.25)
    step_r = P(hold, fr=V(-0.13, -0.05, 0.11), pr=-0.3, yr=-0.3, pel=V(0.04, -0.06, -0.04), prot=(0.08, 0.03, 0.25))
    land_r = P(i, fl=ST_L, yl=-0.25, pel=V(0.03, -0.06, -0.025), prot=(0.05, 0.04, 0.1))
    step_l = P(land_r, fl=V(0.11, -0.10, 0.10), pl=-0.3, yl=0.0, pel=V(-0.01, -0.03, -0.02))
    keys = [(0.0, ready), (T_CHARGE, charge), (0.56, whip), (T_RELEASE, release), (0.82, follow), (1.25, hold), (1.4, hold),
            (1.55, step_r), (1.7, land_r), (1.85, step_l), (2.0, i), (2.3, i)]
    return keyed(keys), 2.3


def throw_crouch(rig):
    i = I(rig)
    st = dict(fl=CR_L, fr=CR_R, yl=-0.2, yr=-0.3, pr=-1.1, kr=V(0, -1, -0.8))
    ready = P(i, pel=V(-0.02, 0.04, -0.30), prot=(0.3, -0.03, -0.2), sp=(0.1, 0.0, -0.15),
              neck=(0.0, 0.0, 0.12), head=(0.0, 0.0, 0.2),
              hr=V(-0.24, -0.10, 0.74), er=V(-0.4, 0.8, -0.3), hl=V(0.22, -0.12, 0.78), gr=0.85, gl=0.3, **st)
    charge = P(ready, pel=V(-0.05, 0.08, -0.36), prot=(0.36, -0.08, -0.45), sp=(0.25, -0.05, -0.45),
               neck=(0.0, 0.0, 0.4), head=(-0.05, 0.06, 0.45),
               hr=V(-0.32, 0.24, 0.78), er=V(-0.3, 0.5, -1.0), hl=V(0.24, -0.34, 0.9), el=V(0.6, 0.2, -0.6), gr=0.95)
    whip = P(charge, pel=V(-0.03, 0.03, -0.35), prot=(0.38, -0.03, -0.1), sp=(0.3, 0.0, -0.1),
             hr=V(-0.34, 0.02, 0.66), neck=(0, 0, 0.1), head=(0.0, 0.0, 0.1))
    release = P(charge, pel=V(0.0, -0.02, -0.34), prot=(0.4, 0.03, 0.22), sp=(0.35, 0.05, 0.22),
                neck=(-0.05, 0.0, -0.2), head=(-0.1, 0.0, -0.25),
                hr=V(-0.30, -0.24, 0.20), hrw=1.0, er=V(-0.5, 0.5, -1.0), hl=V(0.30, 0.06, 0.84), el=V(0.6, 0.8, 0.0), gr=0.4)
    follow = P(release, pel=V(0.02, -0.04, -0.33), prot=(0.45, 0.05, 0.45), sp=(0.4, 0.05, 0.35),
               neck=(-0.05, 0.0, -0.3), head=(-0.15, 0.0, -0.45),
               hr=V(0.06, -0.27, 0.26), er=V(-0.3, 1.0, -0.3), hl=V(0.27, 0.2, 0.78), gr=0.2)
    hold = P(follow, pel=V(0.0, 0.0, -0.31), prot=(0.3, 0.02, 0.3), sp=(0.2, 0.0, 0.15),
             neck=(0.0, 0.0, -0.3), head=(0.0, 0.0, -0.4), hr=V(-0.12, -0.25, 0.72), hrw=0.0, hl=V(0.2, -0.2, 0.76), gr=0.25)
    rise = P(hold, pel=V(0.0, 0.0, -0.12), prot=(0.15, 0.0, 0.15), fr=V(-0.13, 0.1, 0.13), pr=-0.4, kr=None)
    land_r = P(i, fl=CR_L, yl=-0.2, pel=V(0.02, -0.08, -0.04), prot=(0.06, 0.03, 0.08))
    step_l = P(land_r, fl=V(0.11, -0.13, 0.10), pl=-0.3, yl=0.0, pel=V(-0.01, -0.03, -0.02))
    keys = [(0.0, ready), (T_CHARGE, charge), (0.56, whip), (T_RELEASE, release), (0.82, follow), (1.25, hold), (1.45, hold),
            (1.7, rise), (1.85, land_r), (2.0, step_l), (2.15, i), (2.4, i)]
    return keyed(keys), 2.4


def cheer(rig):
    i = I(rig)
    up = dict(hl=V(0.27, -0.04, 1.48), hr=V(-0.27, -0.04, 1.48), el=V(1.0, 0.3, -0.2), er=V(-1.0, 0.3, -0.2), gl=1.0, gr=1.0)
    dip = P(i, pel=V(0.0, 0.0, -0.09), prot=(0.15, 0, 0), sp=(0.1, 0, 0), hl=V(0.2, 0.06, 0.82), hr=V(-0.2, 0.06, 0.82), gl=0.9, gr=0.9)
    keys = [(0.0, i), (0.18, dip)]
    t = 0.32
    for n in range(3):
        h = 0.09 * (1 - n * 0.2)
        air = P(i, pel=V(0.0, 0.0, h), prot=(-0.05, 0, 0), sp=(-0.12, 0, 0), head=(-0.25, 0, 0),
                fl=V(0.095, 0.0, 0.055 + h * 0.9), fr=V(-0.095, 0.02, 0.055 + h * 0.9), pl=-0.45, pr=-0.45, **up)
        land = P(i, pel=V(0.0, 0.0, -0.06), prot=(0.1, 0, 0), sp=(0.0, 0, 0), head=(-0.15, 0, 0), **up)
        keys += [(t, air), (t + 0.17, land)]
        t += 0.42
    w = 0.22
    wave = []
    for n in range(4):
        sgn = 1 if n % 2 == 0 else -1
        wave.append((t + 0.15 + n * w, P(i, pel=V(0.0, 0, -0.01), sp=(-0.05, 0.04 * sgn, 0.05 * sgn), head=(-0.15, -0.05 * sgn, 0.1 * sgn),
                                         hr=V(-0.22 - 0.12 * sgn, -0.05, 1.5), er=V(-1.0, 0.3, -0.2), gr=0.1,
                                         hl=V(0.2, 0.0, 0.82), gl=0.4)))
    keys += wave + [(t + 0.15 + 4 * w + 0.35, i)]
    return keyed(keys), keys[-1][0] + 0.2


def oops(rig):
    i = I(rig)
    hands = dict(hl=V(0.12, -0.06, 1.36), hr=V(-0.12, -0.06, 1.36), el=V(1.0, -0.2, 0.1), er=V(-1.0, -0.2, 0.1), gl=0.2, gr=0.2)
    grab = P(i, pel=V(0, 0.02, -0.04), prot=(0.08, 0, 0), sp=(0.15, 0, 0), neck=(0.15, 0, 0), head=(0.2, 0, 0), **hands)
    keys = [(0.0, i), (0.3, grab)]
    for n in range(4):
        sgn = 1 if n % 2 == 0 else -1
        keys.append((0.5 + n * 0.22, P(grab, neck=(0.15, 0, 0.12 * sgn), head=(0.22, 0.04 * sgn, 0.18 * sgn))))
    slump = P(i, pel=V(0, 0.0, -0.025), prot=(0.05, 0, 0), sp=(0.2, 0, 0), head=(0.25, 0, 0), clav_l=(0.1, 0, 0), clav_r=(0.1, 0, 0),
              hl=V(0.18, -0.02, 0.73), hr=V(-0.18, -0.02, 0.73))
    keys += [(1.55, slump), (2.1, slump), (2.6, i)]
    return keyed(keys), 2.6


# ---- resting: hammock ("sleep") and towel ("sun")
# Clip time runs 0..1 and is seeked by main.gd's progress (sit_k / lie_k, eased). Lying poses are
# authored upright in the body frame: main.gd tips the whole boy back onto the hammock / towel.

def hammock_poses(rig):
    i = I(rig)
    seated = P(i, pel=V(0.0, 0.06, -0.245), prot=(0.1, 0, 0), sp=(0.08, 0, 0), head=(0.05, 0, 0),
               fl=V(0.10, -0.30, 0.10), fr=V(-0.10, -0.29, 0.11), yl=0.1, yr=-0.1, pl=-0.35, pr=-0.3,
               kl=V(0, -1, 0.3), kr=V(0, -1, 0.3),
               hl=V(0.24, 0.05, 0.52), hr=V(-0.24, 0.05, 0.52), hlw=1.0, hrw=1.0, el=V(0.5, 1, 0), er=V(-0.5, 1, 0), gl=0.5, gr=0.5)
    lying = P(i, pel=V(0, 0, 0), prot=(-0.12, 0, 0), sp=(0.06, 0, 0), neck=(0.1, 0, 0), head=(0.22, 0.0, 0.08),
              fl=V(0.06, -0.16, 0.12), fr=V(-0.03, -0.14, 0.15), yl=0.25, yr=-0.25, pl=-0.6, pr=-0.6,
              kl=V(0, -1, 0), kr=V(0, -1, 0),
              hl=V(0.05, -0.16, 0.88), hr=V(-0.05, -0.15, 0.92), el=V(1, 0.3, -0.3), er=V(-1, 0.3, -0.3), gl=0.4, gr=0.4)
    return i, seated, lying


def hammock_clips(rig):
    i, seated, lying = hammock_poses(rig)
    half_sit = P(i, pel=V(0, 0.12, -0.24), prot=(0.35, 0, 0), sp=(0.15, 0, 0),
                 hl=V(0.24, 0.2, 0.75), hr=V(-0.24, 0.2, 0.75), el=V(0.3, 1, -0.3), er=V(-0.3, 1, -0.3))
    sit = keyed([(0.0, i), (0.5, half_sit), (1.0, seated)])
    lean = P(seated, prot=(-0.05, 0, 0), sp=(0.25, 0, 0), fl=V(0.1, -0.36, 0.28), fr=V(-0.1, -0.34, 0.3), pl=-0.4, pr=-0.4,
             hl=V(0.24, 0.15, 0.70), hr=V(-0.24, 0.15, 0.70), hlw=0.0, hrw=0.0)
    lie = keyed([(0.0, seated), (0.5, lean), (1.0, lying)])

    def sleep(t):
        br = math.sin(TAU * t / 4.0 * 3)
        p = dict(lying)
        p["sp"] = (0.06 + 0.02 * br, 0, 0)
        p["head"] = (0.22 - 0.015 * br, 0.03 * math.sin(TAU * t / 4.0), 0.08)
        p["hl"] = lying["hl"] + V(0, -0.006 * br, 0)
        p["hr"] = lying["hr"] + V(0, -0.006 * br, 0)
        return p
    curl = P(lying, sp=(0.45, 0, 0), neck=(0.2, 0, 0), fl=V(0.1, -0.36, 0.42), fr=V(-0.1, -0.34, 0.44), pl=-0.3, pr=-0.3,
             hl=V(0.26, 0.05, 0.56), hr=V(-0.26, 0.05, 0.56), hlw=1.0, hrw=1.0, el=V(0.5, 1, 0), er=V(-0.5, 1, 0))
    up = keyed([(0.0, lying), (0.5, curl), (1.0, seated)])
    push = P(seated, pel=V(0, 0.02, -0.25), prot=(0.55, 0, 0), sp=(0.2, 0, 0), head=(-0.2, 0, 0),
             fl=V(0.10, -0.16, 0.055), fr=V(-0.10, -0.15, 0.055), pl=0.0, pr=0.0,
             hl=V(0.13, -0.27, 0.47), hr=V(-0.13, -0.27, 0.47), el=V(0.6, 0.5, 0), er=V(-0.6, 0.5, 0))
    stand = keyed([(0.0, seated), (0.45, push), (1.0, i)])
    return {"hammock_sit": sit, "hammock_lie": lie, "hammock_sleep": sleep, "hammock_up": up, "hammock_stand": stand}


def towel_poses(rig):
    i = I(rig)
    seated = P(i, pel=V(0.0, 0.20, -0.59), prot=(-0.25, 0, 0), sp=(0.12, 0, 0), neck=(0.05, 0, 0), head=(0.12, 0, 0),
               fl=V(0.11, -0.38, 0.055), fr=V(-0.11, -0.36, 0.055), yl=0.25, yr=-0.25, pl=0.6, pr=0.6,
               kl=V(0, -0.3, 1), kr=V(0, -0.3, 1),
               hl=V(0.2, 0.42, 0.02), hr=V(-0.2, 0.42, 0.02), hlw=1.0, hrw=1.0, el=V(0.3, 1, 0.2), er=V(-0.3, 1, 0.2), gl=0.3, gr=0.3)
    lying = P(i, pel=V(0, 0, 0), prot=(0.0, 0, 0), sp=(0.0, 0, 0), neck=(0.05, 0, 0), head=(0.12, 0, 0),
              fl=V(0.09, 0.0, 0.055), fr=V(-0.10, 0.03, 0.33), yl=0.35, yr=-0.1, pl=-1.0, pr=-1.45,
              kl=V(0, -1, 0), kr=V(0.2, -1, 0),
              hl=V(0.07, 0.08, 1.40), hr=V(-0.07, 0.08, 1.40), el=V(1, -0.3, 0.3), er=V(-1, -0.3, 0.3), gl=0.3, gr=0.3)
    return i, seated, lying


def towel_clips(rig):
    i, seated, lying = towel_poses(rig)
    squat = P(i, pel=V(0, 0.05, -0.36), prot=(0.45, 0, 0), sp=(0.15, 0, 0), pl=-0.2, pr=-0.2,
              hl=V(0.15, -0.3, 0.9), hr=V(-0.15, -0.3, 0.9), el=V(0.6, 0.6, -0.5), er=V(-0.6, 0.6, -0.5))
    lower = P(squat, pel=V(0, 0.17, -0.52), prot=(0.15, 0, 0), sp=(0.1, 0, 0), pl=0.0, pr=0.0,
              fl=V(0.1, -0.12, 0.055), fr=V(-0.1, -0.1, 0.055),
              hl=V(0.2, 0.30, 0.03), hr=V(-0.2, 0.30, 0.03), hlw=1.0, hrw=1.0, el=V(0.3, 1, 0.2), er=V(-0.3, 1, 0.2))
    sit = keyed([(0.0, i), (0.4, squat), (0.7, lower), (1.0, seated)])
    # lying back: legs stay on the towel while main.gd tips the body frame back
    elbows = P(seated, pel=V(0, 0.1, -0.3), prot=(-0.1, 0, 0), sp=(0.3, 0, 0), head=(0.3, 0, 0),
               fl=V(0.1, -0.33, 0.03), fr=V(-0.1, -0.32, 0.05), pl=0.0, pr=0.0,
               hl=V(0.22, 0.12, 0.72), hr=V(-0.22, 0.12, 0.72), hlw=0.0, hrw=0.0, el=V(0.4, 1, -0.3), er=V(-0.4, 1, -0.3))
    lie = keyed([(0.0, seated), (0.5, elbows), (1.0, lying)])

    def rest(t):
        br = math.sin(TAU * t / 4.0 * 3)
        tap = max(math.sin(TAU * t / 4.0 * 5), 0.0)
        p = dict(lying)
        p["sp"] = (0.015 * br, 0, 0)
        p["pr"] = -1.45 + 0.35 * tap
        p["head"] = (0.12, 0.0, 0.06 * math.sin(TAU * t / 4.0))
        return p
    crunch = P(lying, pel=V(0, 0.05, -0.2), prot=(0.0, 0, 0), sp=(0.6, 0, 0), neck=(0.2, 0, 0), head=(0.1, 0, 0),
               fl=V(0.1, -0.3, 0.30), fr=V(-0.1, -0.28, 0.32), pl=0.0, pr=0.0, kl=V(0, -1, 0.3), kr=V(0, -1, 0.3),
               hl=V(0.15, -0.36, 0.86), hr=V(-0.15, -0.36, 0.86), el=V(0.6, 0.6, -0.4), er=V(-0.6, 0.6, -0.4))
    up = keyed([(0.0, lying), (0.5, crunch), (1.0, seated)])
    tuck = P(seated, pel=V(0, 0.16, -0.57), prot=(0.2, 0, 0), sp=(0.25, 0, 0), head=(-0.05, 0, 0),
             fl=V(0.1, -0.08, 0.055), fr=V(-0.1, -0.06, 0.055), pl=0.0, pr=0.0, kl=None, kr=None,
             hl=V(0.16, -0.25, 0.75), hr=V(-0.27, 0.12, 0.02), hlw=0.0, hrw=1.0, el=V(0.6, 0.6, -0.4))
    rise = P(i, pel=V(0, 0.05, -0.34), prot=(0.5, 0, 0), sp=(0.2, 0, 0), pl=-0.1, pr=-0.1,
             hl=V(0.14, -0.3, 0.88), hr=V(-0.14, -0.3, 0.88), el=V(0.6, 0.6, -0.5), er=V(-0.6, 0.6, -0.5))
    stand = keyed([(0.0, seated), (0.35, tuck), (0.68, rise), (1.0, i)])
    return {"sun_sit": sit, "sun_lie": lie, "sun_rest": rest, "sun_up": up, "sun_stand": stand}
