"""Animation clips for the v6 boy, written as functions of time over posekit poses.

Locomotion cycles are procedural (exact, slide-free stance phases); actions are key poses
interpolated with Catmull-Rom. Distances are in Blender units (the boy is 1.48 m tall here;
Godot scales him down).
"""
import math
from mathutils import Vector
from posekit import V, pose, catmull, lerp_pose, solve, GROUND

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
            hl=V(0.232, -0.01, 0.728 + 0.004 * br), hr=V(-0.232, 0.0, 0.728 + 0.004 * br),
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


# throwing stances: left foot forward, right foot back, body side-on to the target (-Y)
ST_L, ST_R = V(0.10, -0.12, 0.055), V(-0.17, 0.24, 0.055)   # set-up; the weight rocks back onto the right foot
ST_L2 = V(0.12, -0.30, 0.055)                               # front foot after the stride into the throw
CR_L, CR_R = V(0.11, -0.30, 0.055), V(-0.14, 0.34, 0.055)
T_CHARGE = 0.5      # charge part of the throw clips: seek 0..T_CHARGE by power
T_RELEASE = 0.65    # stone leaves the hand


def _idle_hand_r(rig, i):
    """idle right-hand target in root space (the chest is almost square at idle, so it is where hrw=0 lands)"""
    M, _ = solve(rig, i)
    return M["hand_r"].translation.copy()


def _recover(rig, i, last, t0, fl_from):
    """from `last` (arm already falling, torso unwinding): the relaxed arm swings past the right side like a
    pendulum, overshoots a little behind the hip, swings back and settles while the back foot steps up, the
    front foot steps back and the weight dips onto both feet. Hands stay in root space until the body is square."""
    R0 = _idle_hand_r(rig, i)
    loose_l = dict(hl=V(0.21, 0.0, 0.75), hlw=0.0, el=i["el"], gl=0.3)
    swing = P(last, fr=V(-0.12, 0.10, 0.10), pr=-0.25, yr=-0.15, kr=None, pel=V(0.03, -0.08, -0.07),
              prot=(0.10, 0.02, 0.20), sp=(0.05, 0.0, 0.10), neck=(0.0, 0.0, -0.12), head=(0.02, 0.0, -0.12),
              hr=R0 + V(0.06, -0.09, 0.012), hrw=1.0, er=V(-0.3, 1.0, 0.0), wr=(0.10, 0.0, 0.0), gr=0.3,
              clav_r=(0.0, 0.0, 0.0), **loose_l)
    behind = P(swing, fr=i["fr"], pr=0.0, yr=i["yr"], pel=V(0.01, -0.05, -0.036), prot=(0.05, 0.02, 0.07),
               sp=(0.01, 0.0, 0.03), neck=(0.0, 0.0, -0.04), head=(0.03, 0.0, -0.04),
               hr=R0 + V(-0.015, 0.075, -0.004), wr=(-0.12, 0.0, 0.0), hl=V(0.225, 0.02, 0.74))
    step_l = P(behind, fl=(fl_from + i["fl"]) * 0.5 + V(0, 0, 0.045), pl=-0.2, yl=0.05, pel=V(-0.01, -0.02, -0.03),
               prot=(0.02, 0.03, 0.02), sp=(0.0, 0.0, 0.0), neck=(0.0, 0.0, 0.0), head=(0.04, 0.0, 0.0),
               hr=R0 + V(0.0, -0.032, 0.0), wr=(0.06, 0.0, 0.0), hl=V(0.23, -0.012, 0.735))
    land_l = P(i, pel=V(0.0, 0.0, -0.026), prot=(0.015, 0.0, 0.0), sp=(-0.02, 0.0, 0.0),
               hr=R0 + V(-0.002, 0.012, 0.0), hrw=1.0, er=V(-0.4, 1.0, 0.0))
    return [(t0, swing), (t0 + 0.15, behind), (t0 + 0.30, step_l), (t0 + 0.45, land_l), (t0 + 0.63, i), (t0 + 0.8, i)]


def throw_stand(rig):
    """sidearm skip throw as a kinetic chain: coil onto the back foot with the stone drawn back low, stride and
    plant, pelvis opens first while the chest stays closed, the elbow leads with the forearm laid back, chest
    rotation and elbow extension carry the hand forward, low flat release with a wrist snap, the arm keeps
    reaching out towards the water, then decelerates across to the left side, step up and settle"""
    i = I(rig)
    st = dict(fl=ST_L, fr=ST_R, yl=-0.35, yr=-1.1)
    ready = P(i, pel=V(-0.02, 0.04, -0.05), prot=(0.10, -0.02, -0.55), sp=(0.06, 0.0, -0.12),
              neck=(0.0, 0.0, 0.28), head=(0.05, 0.0, 0.32),
              hr=V(-0.22, -0.06, 0.74), er=V(-0.5, 0.6, -0.5), hl=V(0.20, -0.14, 0.80), el=V(0.5, 0.6, -0.4),
              gr=0.85, gl=0.35, **st)
    charge = P(ready, pel=V(-0.07, 0.11, -0.12), prot=(0.20, -0.07, -0.85), sp=(0.18, -0.10, -0.40),
               neck=(0.0, 0.0, 0.52), head=(0.05, 0.05, 0.58),
               hr=V(-0.30, 0.36, 0.66), hrw=1.0, er=V(-0.2, 0.4, -1.0), wr=(0.0, 0.0, -0.5), gr=0.95,
               hl=V(0.10, -0.34, 0.95), hlw=1.0, el=V(0.6, 0.2, -0.6), gl=0.15, pl=-0.25)
    stride = P(charge, pel=V(-0.05, 0.05, -0.12), prot=(0.22, -0.07, -0.62), sp=(0.20, -0.14, -0.42),
               fl=(ST_L + ST_L2) * 0.5 + V(0, 0, 0.04), pl=0.1, yl=-0.3, hr=V(-0.36, 0.32, 0.62), wr=(0.0, 0.0, -0.65))
    # foot down: hips already square to the target, chest still closed, hand lags behind the leading elbow
    plant = P(charge, pel=V(-0.01, -0.06, -0.15), prot=(0.26, -0.05, -0.12), sp=(0.24, -0.18, -0.42),
              neck=(0.0, 0.0, 0.3), head=(0.0, 0.0, 0.3), fl=ST_L2, pl=0.0, yl=-0.25,
              hr=V(-0.46, 0.08, 0.62), wr=(0.0, 0.0, -0.75), er=V(-0.2, -0.4, -1.0),
              hl=V(0.22, -0.20, 0.86), pr=-0.3, yr=-0.95)
    accel = P(plant, pel=V(0.0, -0.10, -0.15), prot=(0.28, -0.02, 0.05), sp=(0.26, -0.20, -0.15),
              neck=(0.0, 0.0, 0.1), head=(0.0, 0.0, 0.05),
              hr=V(-0.46, -0.18, 0.62), wr=(0.0, 0.0, -0.4), er=V(-0.4, 0.2, -1.0),
              hl=V(0.26, -0.10, 0.86), hlw=0.0, el=V(0.8, 0.6, -0.2), pr=-0.45, yr=-0.8)
    release = P(accel, pel=V(0.02, -0.14, -0.15), prot=(0.30, 0.0, 0.18), sp=(0.30, -0.18, 0.12),
                neck=(-0.05, 0.0, -0.15), head=(0.0, 0.0, -0.12),
                hr=V(-0.38, -0.44, 0.61), wr=(0.0, 0.0, 0.5), er=V(-0.3, 0.3, -1.0), gr=0.4,
                hl=V(0.24, -0.04, 0.86), pr=-0.6, yr=-0.7)
    # the arm keeps travelling out towards the water, nearly straight
    reach = P(release, pel=V(0.03, -0.19, -0.15), prot=(0.34, 0.02, 0.36), sp=(0.30, -0.10, 0.26),
              neck=(-0.05, 0.0, -0.3), head=(-0.05, 0.0, -0.32),
              hr=V(-0.24, -0.76, 0.68), wr=(0.0, 0.0, 0.6), er=V(-0.2, 0.2, -1.0), gr=0.3,
              hl=V(0.22, 0.02, 0.84), pr=-0.85, yr=-0.5)
    reach2 = P(reach, pel=V(0.035, -0.19, -0.145), prot=(0.34, 0.025, 0.45), sp=(0.28, -0.07, 0.29),
               hr=V(-0.13, -0.74, 0.68), wr=(0.0, 0.0, 0.45), er=V(-0.1, 0.4, -1.0), pr=-0.92, yr=-0.4)
    # deceleration: the arm sweeps across to the left side, the chest keeps turning and bends over
    sweep = P(reach2, pel=V(0.04, -0.19, -0.14), prot=(0.34, 0.03, 0.55), sp=(0.24, -0.04, 0.32),
              neck=(-0.05, 0.0, -0.4), head=(-0.05, 0.0, -0.42),
              hr=V(0.10, -0.54, 0.66), wr=(0.0, 0.0, 0.3), er=V(0.0, 0.6, -1.0), gr=0.25,
              hl=V(0.20, -0.04, 0.82), pr=-1.0, yr=-0.3)
    wrap = P(sweep, pel=V(0.05, -0.16, -0.11), prot=(0.24, 0.04, 0.62), sp=(0.16, 0.0, 0.36),
             neck=(0.0, 0.0, -0.4), head=(0.0, 0.0, -0.45),
             hr=V(0.30, -0.20, 0.72), er=V(0.3, 1.0, -0.4), wr=(0.0, 0.0, 0.0), hl=V(0.20, -0.08, 0.80), pr=-1.0, yr=-0.2,
             clav_r=(0.10, 0.0, 0.06))
    # the arm has run out of speed: it goes limp (elbow folds, shoulder drops) and starts to fall while the
    # chest unwinds back towards the target
    loose = P(wrap, pel=V(0.05, -0.155, -0.105), prot=(0.20, 0.04, 0.56), sp=(0.13, 0.0, 0.32),
              neck=(0.0, 0.0, -0.36), head=(0.02, 0.0, -0.40),
              hr=V(0.26, -0.16, 0.70), er=V(0.1, 1.0, -0.5), wr=(0.2, 0.0, 0.0), gr=0.35, clav_r=(0.04, 0.0, 0.0))
    fall = P(loose, pel=V(0.045, -0.13, -0.09), prot=(0.15, 0.03, 0.40), sp=(0.09, 0.0, 0.22),
             neck=(0.0, 0.0, -0.25), head=(0.02, 0.0, -0.28),
             hr=V(0.04, -0.20, 0.69), er=V(-0.2, 1.0, -0.2), wr=(0.15, 0.0, 0.0), clav_r=(0.0, 0.0, 0.0), pr=-0.7, yr=-0.4)
    keys = [(0.0, ready), (T_CHARGE, charge), (0.555, stride), (0.60, plant), (0.625, accel), (T_RELEASE, release),
            (0.71, reach), (0.76, reach2), (0.86, sweep), (0.99, wrap), (1.11, loose), (1.25, fall)] + _recover(rig, i, fall, 1.40, ST_L2)
    return keyed(keys), keys[-1][0]


def throw_crouch(rig):
    """the same chain from a half kneel (right knee down): lower and flatter, then stand up and settle"""
    i = I(rig)
    st = dict(fl=CR_L, fr=CR_R, yl=-0.35, yr=-0.6, pr=-1.1, kr=V(0, -1, -0.8))
    ready = P(i, pel=V(-0.02, 0.06, -0.30), prot=(0.30, -0.03, -0.5), sp=(0.12, 0.0, -0.15),
              neck=(0.0, 0.0, 0.3), head=(0.0, 0.0, 0.35),
              hr=V(-0.24, -0.10, 0.74), er=V(-0.4, 0.8, -0.3), hl=V(0.22, -0.12, 0.78), el=V(0.5, 0.6, -0.4),
              gr=0.85, gl=0.3, **st)
    charge = P(ready, pel=V(-0.06, 0.10, -0.35), prot=(0.40, -0.10, -0.85), sp=(0.25, -0.10, -0.40),
               neck=(0.0, 0.0, 0.55), head=(-0.05, 0.05, 0.6),
               hr=V(-0.30, 0.34, 0.36), hrw=1.0, er=V(-0.2, 0.4, -1.0), wr=(0.0, 0.0, -0.5), gr=0.95,
               hl=V(0.12, -0.42, 0.70), hlw=1.0, el=V(0.6, 0.2, -0.6), gl=0.15)
    drive = P(charge, pel=V(-0.03, 0.03, -0.36), prot=(0.42, -0.08, -0.45), sp=(0.28, -0.14, -0.42),
              hr=V(-0.38, 0.26, 0.32), wr=(0.0, 0.0, -0.65))
    plant = P(charge, pel=V(-0.01, -0.02, -0.36), prot=(0.42, -0.06, -0.12), sp=(0.30, -0.16, -0.42),
              neck=(0.0, 0.0, 0.3), head=(0.0, 0.0, 0.3),
              hr=V(-0.46, 0.08, 0.30), wr=(0.0, 0.0, -0.75), er=V(-0.2, -0.4, -1.0), hl=V(0.22, -0.22, 0.66))
    accel = P(plant, pel=V(0.0, -0.05, -0.35), prot=(0.44, -0.03, 0.05), sp=(0.32, -0.18, -0.15),
              neck=(0.0, 0.0, 0.1), head=(-0.04, 0.0, 0.05),
              hr=V(-0.46, -0.16, 0.28), wr=(0.0, 0.0, -0.4), er=V(-0.4, 0.2, -1.0),
              hl=V(0.26, -0.10, 0.86), hlw=0.0, el=V(0.8, 0.6, -0.2))
    release = P(accel, pel=V(0.01, -0.08, -0.35), prot=(0.46, 0.0, 0.18), sp=(0.36, -0.16, 0.12),
                neck=(-0.05, 0.0, -0.15), head=(-0.08, 0.0, -0.12),
                hr=V(-0.38, -0.40, 0.27), wr=(0.0, 0.0, 0.5), er=V(-0.3, 0.3, -1.0), gr=0.4, hl=V(0.24, -0.04, 0.86))
    reach = P(release, pel=V(0.02, -0.12, -0.34), prot=(0.50, 0.02, 0.36), sp=(0.38, -0.08, 0.26),
              neck=(-0.05, 0.0, -0.3), head=(-0.1, 0.0, -0.32),
              hr=V(-0.24, -0.70, 0.34), wr=(0.0, 0.0, 0.6), er=V(-0.2, 0.2, -1.0), gr=0.3, hl=V(0.22, 0.02, 0.84))
    reach2 = P(reach, pel=V(0.025, -0.115, -0.34), prot=(0.50, 0.025, 0.45), sp=(0.36, -0.05, 0.28),
               hr=V(-0.13, -0.68, 0.35), wr=(0.0, 0.0, 0.45), er=V(-0.1, 0.4, -1.0))
    sweep = P(reach2, pel=V(0.03, -0.11, -0.34), prot=(0.50, 0.03, 0.52), sp=(0.34, -0.03, 0.30),
              neck=(-0.05, 0.0, -0.4), head=(-0.1, 0.0, -0.42),
              hr=V(0.10, -0.50, 0.38), wr=(0.0, 0.0, 0.3), er=V(0.0, 0.6, -1.0), gr=0.25, hl=V(0.20, -0.04, 0.82))
    wrap = P(sweep, pel=V(0.04, -0.09, -0.33), prot=(0.45, 0.04, 0.58), sp=(0.30, 0.0, 0.34),
             neck=(0.0, 0.0, -0.4), head=(-0.05, 0.0, -0.45),
             hr=V(0.28, -0.20, 0.46), er=V(0.3, 1.0, -0.4), wr=(0.0, 0.0, 0.0), hl=V(0.20, -0.08, 0.80),
             clav_r=(0.10, 0.0, 0.06))
    loose = P(wrap, pel=V(0.04, -0.095, -0.325), prot=(0.47, 0.04, 0.52), sp=(0.30, 0.0, 0.30),
              hr=V(0.24, -0.16, 0.42), er=V(0.1, 1.0, -0.5), wr=(0.2, 0.0, 0.0), gr=0.35, clav_r=(0.04, 0.0, 0.0))
    # stand up: weight onto the front foot, push off the back knee; the limp arm falls past the front knee
    lean = P(loose, pel=V(0.02, -0.13, -0.30), prot=(0.60, 0.02, 0.28), sp=(0.22, 0.0, 0.14),
             hr=V(0.04, -0.27, 0.43), er=V(-0.2, 1.0, -0.2), wr=(0.15, 0.0, 0.0), clav_r=(0.0, 0.0, 0.0),
             hl=V(0.18, -0.30, 0.62), hlw=0.0, el=i["el"],
             neck=(0.0, 0.0, -0.22), head=(-0.15, 0.0, -0.22), gr=0.3, gl=0.3)
    rise = P(lean, pel=V(0.02, -0.11, -0.15), prot=(0.28, 0.02, 0.22), fr=V(-0.13, 0.18, 0.10), pr=-0.5, kr=None,
             hr=V(-0.10, -0.22, 0.62), hl=V(0.21, -0.06, 0.74), head=(-0.05, 0.0, -0.18))
    keys = [(0.0, ready), (T_CHARGE, charge), (0.56, drive), (0.60, plant), (0.625, accel), (T_RELEASE, release),
            (0.71, reach), (0.76, reach2), (0.86, sweep), (0.99, wrap), (1.11, loose), (1.29, lean), (1.49, rise)] \
        + _recover(rig, i, rise, 1.65, CR_L)
    return keyed(keys), keys[-1][0]


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


# ---- sitting on a bench / log / lounger edge (seat top ~0.35 m in game, 0.40 here)
SEAT_PEL = V(0.0, 0.13, -0.30)


def seat_poses(rig):
    i = I(rig)
    seated = P(i, pel=SEAT_PEL, prot=(-0.08, 0, 0), sp=(0.14, 0, 0), neck=(0.02, 0, 0), head=(0.06, 0, 0),
               fl=V(0.12, -0.20, 0.055), fr=V(-0.12, -0.19, 0.055), yl=0.15, yr=-0.15, pl=0.0, pr=0.0,
               kl=V(0.1, -1, 0), kr=V(-0.1, -1, 0),
               hl=V(0.15, -0.20, 0.47), hr=V(-0.15, -0.19, 0.47), hlw=1.0, hrw=1.0,
               el=V(0.6, 0.6, -0.4), er=V(-0.6, 0.6, -0.4), gl=0.4, gr=0.4)
    return i, seated


# lying on the back along the bench / log, authored upright (main.gd tips the body frame onto the seat, head
# towards his right): right knee raised with the foot flat on the seat, left ankle crossed over that knee,
# hands behind the head (the hat goes over his face in boy.gd)
KNEE_R = V(-0.036, -0.316, 0.651)


def seat_lying(rig):
    i = I(rig)
    return P(i, pel=V(0, 0, 0), prot=(0.0, 0, 0), sp=(0.03, 0, 0), neck=(0.06, 0, 0), head=(0.08, 0.0, 0.0),
             fr=V(-0.10, 0.03, 0.33), yr=-0.1, pr=-1.45, kr=V(0.2, -1, 0),
             fl=KNEE_R + V(0.0, -0.075, 0.015), yl=0.5, pl=0.0, kl=V(1.0, -0.8, 0.3),
             hl=V(0.07, 0.08, 1.40), hr=V(-0.07, 0.08, 1.40), hlw=0.0, hrw=0.0,
             el=V(1, -0.3, 0.3), er=V(-1, -0.3, 0.3), gl=0.3, gr=0.3)


def seat_clips(rig):
    i, seated = seat_poses(rig)
    lying = seat_lying(rig)
    # look back at the seat, bend the knees, reach behind for it, lower
    bend = P(i, pel=V(0.0, 0.05, -0.12), prot=(0.30, 0, 0.12), sp=(0.12, 0, 0), head=(-0.05, 0, 0.25),
             fl=V(0.11, -0.10, 0.055), fr=V(-0.11, -0.09, 0.055), pl=0.0, pr=0.0, kl=V(0.1, -1, 0), kr=V(-0.1, -1, 0),
             hl=V(0.24, 0.08, 0.60), hr=V(-0.24, 0.10, 0.56), hlw=1.0, hrw=1.0, el=V(0.6, 0.8, 0), er=V(-0.6, 0.8, 0))
    lower = P(bend, pel=SEAT_PEL + V(0, -0.02, 0.025), prot=(0.30, 0, 0.0), sp=(0.10, 0, 0), head=(0.0, 0, 0.05),
              fl=V(0.12, -0.17, 0.055), fr=V(-0.12, -0.16, 0.055),
              hl=V(0.25, 0.14, 0.42), hr=V(-0.25, 0.14, 0.42), el=V(0.6, 1, 0), er=V(-0.6, 1, 0))
    sit = keyed([(0.0, i), (0.42, bend), (0.78, lower), (1.0, seated)])

    def rest(t):
        """4 s loop: breathe, swing the feet a little, look around"""
        u = TAU * t / 4.0
        br = math.sin(u * 3)
        p = dict(seated)
        p["sp"] = (0.14 + 0.015 * br, 0, 0)
        p["head"] = (0.06 + 0.04 * math.sin(u), 0.0, 0.35 * math.sin(u) * sm(math.sin(u * 0.5) ** 2))
        p["neck"] = (0.02, 0.0, 0.12 * math.sin(u))
        sw = math.sin(u * 2)
        p["fl"] = seated["fl"] + V(0, -0.05 * max(sw, 0.0), 0.04 * max(sw, 0.0))
        p["fr"] = seated["fr"] + V(0, -0.05 * max(-sw, 0.0), 0.04 * max(-sw, 0.0))
        p["pl"] = -0.25 * max(sw, 0.0)
        p["pr"] = -0.25 * max(-sw, 0.0)
        p["hl"] = seated["hl"] + V(0, 0, 0.006 * br)
        p["hr"] = seated["hr"] + V(0, 0, 0.006 * br)
        return p
    # feet back under the seat, lean over them, push up off the knees
    tuck = P(seated, pel=SEAT_PEL + V(0, -0.03, 0.01), prot=(0.45, 0, 0), sp=(0.15, 0, 0), head=(-0.15, 0, 0),
             fl=V(0.11, -0.08, 0.055), fr=V(-0.11, -0.07, 0.055), pl=0.0, pr=0.0,
             hl=V(0.14, -0.22, 0.50), hr=V(-0.14, -0.21, 0.50), el=V(0.7, 0.4, -0.2), er=V(-0.7, 0.4, -0.2))
    push = P(i, pel=V(0.0, -0.02, -0.14), prot=(0.40, 0, 0), sp=(0.1, 0, 0), head=(-0.1, 0, 0),
             fl=V(0.11, -0.08, 0.055), fr=V(-0.11, -0.07, 0.055),
             hl=V(0.16, -0.24, 0.58), hr=V(-0.16, -0.23, 0.58), hlw=1.0, hrw=1.0, el=V(0.7, 0.4, -0.2), er=V(-0.7, 0.4, -0.2))
    stand = keyed([(0.0, seated), (0.3, tuck), (0.62, push), (1.0, i)])
    # lie down (time 0..1 follows main.gd's tip of the body frame): lean onto the right hand on the seat,
    # swing the legs up, settle the right foot, cross the left ankle over the knee, hands behind the head
    prop = P(seated, prot=(-0.05, 0.0, 0.08), sp=(0.10, 0.05, 0.10), head=(0.0, 0.0, 0.2),
             hr=V(-0.30, 0.02, 0.44), hrw=1.0, er=V(-0.8, 0.6, 0.0), gr=0.1,
             hl=V(0.12, -0.22, 0.48), hlw=1.0, fl=V(0.12, -0.24, 0.10), fr=V(-0.12, -0.22, 0.08))
    swing = P(prop, pel=V(0.0, 0.06, -0.15), prot=(-0.04, 0.0, 0.04), sp=(0.06, 0.03, 0.05), head=(0.05, 0.0, 0.1),
              fl=V(0.11, -0.34, 0.30), fr=V(-0.11, -0.30, 0.26), pl=0.2, pr=0.1, kl=V(0.2, -1, 0.2), kr=V(-0.1, -1, 0.2),
              hr=V(-0.20, 0.10, 0.80), hrw=0.0, er=V(-1.0, 0.0, 0.0), hl=V(0.14, -0.06, 0.95), hlw=0.0, el=V(1.0, 0.2, 0.0))
    settle = P(lying, fl=V(0.10, -0.20, 0.30), pl=0.1, yl=0.2, kl=V(0.4, -1, 0.2),
               hl=V(0.12, 0.0, 1.25), hr=V(-0.12, 0.0, 1.25), el=V(1, 0.2, 0.0), er=V(-1, 0.2, 0.0))
    lie = keyed([(0.0, seated), (0.3, prop), (0.6, swing), (0.82, settle), (1.0, lying)])

    def nap(t):
        """4 s loop: slow breathing, the crossed foot bobs to a tune, a hand drums once on the head"""
        u = TAU * t / 4.0
        br = math.sin(u * 2)
        bob = math.sin(u * 4)
        p = dict(lying)
        p["sp"] = (0.03 + 0.02 * br, 0, 0)
        p["pel"] = V(0, 0, 0.004 * br)
        p["pl"] = 0.28 * bob
        p["fl"] = lying["fl"] + V(0.0, -0.012 * max(bob, 0.0), 0.0)
        p["hl"] = lying["hl"] + V(0, -0.006 * br, 0.004 * br)
        p["hr"] = lying["hr"] + V(0, -0.006 * br, 0.004 * br)
        p["head"] = (0.08 - 0.01 * br, 0.0, 0.05 * math.sin(u))
        return p
    up = keyed([(0.0, lying), (0.18, settle), (0.4, swing), (0.7, prop), (1.0, seated)])
    return {"seat_sit": sit, "seat_rest": rest, "seat_stand": stand, "seat_lie": lie, "seat_nap": nap, "seat_up": up}
