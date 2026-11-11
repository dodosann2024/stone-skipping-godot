"""Clothes / hair clipping over the baked poses (v17).

blender -b boy.blend --python art/boy/cloth_check.py -- [OUT.json]

Per pose, counts vertices that came out through the layer that covers them at rest (more than 1.5 mm):
  skin>tank, skin>vest, skin>shorts, tank>vest, shorts>vest   whole garments, not just the shoulders
  hair>skin    hair inside the head / ears / neck
  hair>hat     hair through the hat crown or brim (poses where the hat is on the head)
"""
import bpy, bmesh, sys, os, json
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0, os.path.dirname(__file__))
import posekit, clips

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
TOL = 0.0015
DEBUG = [None] if os.environ.get("POKE_DEBUG") else None
HAT_OFF = ("hammock", "sun")       # the hat sits on his chest / the ground in these (boy.gd hat_mode)


def poses(rig):
    walk = clips.Gait(rig, 1.0, 1.0, 0.62)
    run = clips.Gait(rig, 0.68, 2.04, 0.36, run=True)
    ts, _ = clips.throw_stand(rig)
    tc, _ = clips.throw_crouch(rig)
    ch, lch = clips.cheer(rig)
    hm = clips.hammock_clips(rig)
    tw = clips.towel_clips(rig)
    idle = clips.idle(rig)
    out = [("rest", idle(0.3)), ("raise", ch(lch * 0.45))]
    for k in range(6):
        out.append(("throw%.1f" % (0.3 + 0.1 * k), ts(0.3 + 0.1 * k)))
    for k in range(5):
        out.append(("crouch%.2f" % (0.35 + 0.1 * k), tc(0.35 + 0.1 * k)))
    for k in range(4):
        out.append(("walk%d" % k, walk.pose(walk.T * k / 4)))
        out.append(("run%d" % k, run.pose(run.T * k / 4)))
    out.append(("hammock", hm["hammock_sleep"](1.0)))
    out.append(("sun", tw["sun_rest"](1.0)))
    return out


def evaluated(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    co = [ev.matrix_world @ v.co for v in me.vertices]
    nr = [(ev.matrix_world.to_3x3() @ v.normal).normalized() for v in me.vertices]
    tris = [tuple(p.vertices) for p in me.loop_triangles] if me.loop_triangles else None
    if tris is None:
        me.calc_loop_triangles()
        tris = [tuple(t.vertices) for t in me.loop_triangles]
    ev.to_mesh_clear()
    return co, nr, tris


def bvh(co, tris):
    return BVHTree.FromPolygons(co, tris)


def hits(t, o, d, maxd):
    """surfaces crossed by the ray o + d * s, 0 <= s <= maxd"""
    k = 0
    while maxd > 0:
        loc, n, fi, dist = t.ray_cast(o, d, maxd)
        if loc is None:
            break
        k += 1
        o = loc + d * 1e-5
        maxd -= dist + 1e-5
    return k


def covered(inner, outer_bvh):
    """inner vertices with the garment in front of them (along their normal, within 3 cm)"""
    co, nr = inner
    return [i for i, (c, n) in enumerate(zip(co, nr)) if hits(outer_bvh, c - n * TOL, n, 0.03 + TOL) > 0]


def pokes(inner, outer_bvh, ids):
    """garments are solidified (inner and outer walls), so a vertex is out when nothing of the garment
    is in front of it any more but the garment is right behind it (it went through)"""
    co, nr = inner
    k = 0
    for i in ids:
        c, n = co[i], nr[i]
        if hits(outer_bvh, c - n * TOL, n, 0.05) == 0 and hits(outer_bvh, c - n * TOL, -n, 0.03) > 0:
            k += 1
            if DEBUG:
                DEBUG.append(tuple(round(x, 2) for x in c))
    return k


def main():
    rig_ob = bpy.data.objects["BoyRig"]
    names = [n for n in ("Body", "Tank", "Vest", "Shorts", "Hair", "Hat") if n in bpy.data.objects]
    obs = {n: bpy.data.objects[n] for n in names}
    rig = posekit.Rig(rig_ob)
    pairs = [("Body", "Tank"), ("Body", "Vest"), ("Body", "Shorts"), ("Tank", "Vest"), ("Shorts", "Vest")]
    pairs = [p for p in pairs if p[0] in obs and p[1] in obs]

    posekit.apply_pose(rig, poses(rig)[0][1])
    bpy.context.view_layer.update()
    rest = {n: evaluated(o) for n, o in obs.items()}
    cov = {}
    for a, b in pairs:
        cov[(a, b)] = covered(rest[a][:2], bvh(rest[b][0], rest[b][2]))
    # hair: which card vertices are under the hat, measured along the ray from the head centre
    hc0 = rig_ob.matrix_world @ rig_ob.pose.bones["head"].head
    hair_hat = []
    if "Hair" in rest and "Hat" in rest:
        hb = bvh(rest["Hat"][0], rest["Hat"][2])
        for i, c in enumerate(rest["Hair"][0]):
            d = c - hc0
            loc, n, fi, dist = hb.ray_cast(hc0, d.normalized(), d.length + 0.03)
            if loc is not None and dist > d.length:
                hair_hat.append(i)

    res = {}
    for name, p in poses(rig):
        posekit.apply_pose(rig, p)
        bpy.context.view_layer.update()
        cur = {n: evaluated(o) for n, o in obs.items()}
        r = {}
        for a, b in pairs:
            r["%s>%s" % (a.lower().replace("body", "skin"), b.lower())] = pokes(cur[a][:2], bvh(cur[b][0], cur[b][2]), cov[(a, b)])
        if "Hair" in cur:
            hco = cur["Hair"][0]
            k = 0
            t = bvh(cur["Body"][0], cur["Body"][2])
            for c in hco:
                loc, fn, fi, d = t.find_nearest(c)
                if loc is not None and d < 0.02 and (loc - c).dot(fn) > TOL:
                    k += 1
            r["hair>skin"] = k
            if "Hat" in cur and name not in HAT_OFF:
                hc = rig_ob.matrix_world @ rig_ob.pose.bones["head"].head
                hb = bvh(cur["Hat"][0], cur["Hat"][2])
                k = 0
                for i in hair_hat:
                    d = hco[i] - hc
                    loc, n, fi, dist = hb.ray_cast(hc, d.normalized(), d.length)
                    if loc is not None and dist < d.length - TOL:
                        k += 1
                r["hair>hat"] = k
        if DEBUG and len(DEBUG) > 1:
            print("POKES", name, sorted(set(DEBUG[1:]))[:40])
            del DEBUG[1:]
        res[name] = r
        print("CLOTH %-12s %s" % (name, r))
    keys = sorted({k for r in res.values() for k in r})
    tot = {k: sum(r.get(k, 0) for r in res.values()) for k in keys}
    print("CLOTH TOTAL", tot)
    if ARGS:
        with open(ARGS[0], "w") as f:
            json.dump({"poses": res, "total": tot}, f, indent=1)


main()
