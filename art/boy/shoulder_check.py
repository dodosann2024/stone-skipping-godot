"""Shoulder deformation numbers for the baked poses (v16).

blender -b boy.blend --python art/boy/shoulder_check.py -- [OUT.json]

Per pose, over the skin within 10 cm of either shoulder joint:
  squash   share of triangles that lost > 40 % of their rest area (pinch / candy-wrap)
  minarea  smallest posed / rest triangle area ratio
  folds    edges whose two faces bend > 70 degrees more than at rest (creases)
  shrink   5th percentile of posed / rest distance to the joint centre (collapsing volume)
  poke     vertices that came out through the layer over them (skin / tank top / vest)
"""
import bpy, bmesh, sys, os, json, math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0, os.path.dirname(__file__))
import posekit, clips

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


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
        t = 0.3 + 0.1 * k
        out.append(("throw%.1f" % t, ts(t)))
    for k in range(5):
        t = 0.35 + 0.1 * k
        out.append(("crouch%.2f" % t, tc(t)))
    for k in range(4):
        out.append(("walk%d" % k, walk.pose(walk.T * k / 4)))
        out.append(("run%d" % k, run.pose(run.T * k / 4)))
    out.append(("hammock", hm["hammock_sleep"](1.0)))
    out.append(("sun", tw["sun_rest"](1.0)))
    return out


def mesh_co(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    co = [ev.matrix_world @ v.co for v in me.vertices]
    nr = [(ev.matrix_world.to_3x3() @ v.normal).normalized() for v in me.vertices]
    ev.to_mesh_clear()
    return co, nr


def tri_area(a, b, c):
    return (b - a).cross(c - a).length * 0.5


def main():
    rig_ob = bpy.data.objects["BoyRig"]
    body = bpy.data.objects["Body"]
    cloth = [bpy.data.objects[n] for n in ("Tank", "Vest") if n in bpy.data.objects]
    rig = posekit.Rig(rig_ob)
    me = body.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.verts.ensure_lookup_table()
    tris = [tuple(v.index for v in f.verts) for f in bm.faces]
    edges = []
    for e in bm.edges:
        if len(e.link_faces) == 2:
            edges.append((e.verts[0].index, e.verts[1].index,
                          tuple(v.index for v in e.link_faces[0].verts), tuple(v.index for v in e.link_faces[1].verts)))
    bm.free()
    joints = {s: rig.head["upperarm_" + s] for s in "lr"}

    def near(i, co):
        return min((co[i] - j).length for j in joints.values()) < 0.10

    rest_co = [v.co.copy() for v in me.vertices]
    reg = set(i for i in range(len(rest_co)) if near(i, rest_co))
    rtris = [t for t in tris if all(i in reg for i in t)]
    redges = [e for e in edges if e[0] in reg and e[1] in reg]

    def fnormal(co, t):
        return (co[t[1]] - co[t[0]]).cross(co[t[2]] - co[t[0]]).normalized()

    def bend(co, e):
        return fnormal(co, e[2]).angle(fnormal(co, e[3]), 0.0)

    rest_area = [tri_area(*(rest_co[i] for i in t)) for t in rtris]
    rest_bend = [bend(rest_co, e) for e in redges]
    rest_d = {i: min((rest_co[i] - j).length for j in joints.values()) for i in reg}
    side = {i: ("l" if rest_co[i].x > 0 else "r") for i in reg}

    # layer pairs (inner, outer): inner vertices that sit under the outer layer at rest
    pairs = [(body, ob) for ob in cloth] + ([(cloth[0], cloth[1])] if len(cloth) == 2 else [])

    def bvh_of(ob, co=None):
        cbm = bmesh.new()
        cbm.from_mesh(ob.data)
        if co is not None:
            for v, c in zip(cbm.verts, co):
                v.co = c
        t = BVHTree.FromBMesh(cbm)
        cbm.free()
        return t

    covered = {}
    for inn, out in pairs:
        bvh = bvh_of(out)
        ids = []
        for v in inn.data.vertices:
            if min((v.co - j).length for j in joints.values()) > 0.14:
                continue
            loc, n, fi, d = bvh.find_nearest(v.co)
            if loc is not None and d < 0.02 and (loc - v.co).dot(v.normal) > 0.001:
                ids.append(v.index)
        covered[(inn.name, out.name)] = ids

    res = {}
    for name, p in poses(rig):
        posekit.apply_pose(rig, p)
        bpy.context.view_layer.update()
        co, nr = mesh_co(body)
        jm = {s: (rig_ob.matrix_world @ rig_ob.pose.bones["upperarm_" + s].head) for s in "lr"}
        ratios = []
        for t, a0 in zip(rtris, rest_area):
            if a0 > 1e-9:
                ratios.append(tri_area(*(co[i] for i in t)) / a0)
        squash = sum(1 for r in ratios if r < 0.6) / max(1, len(ratios))
        folds = sum(1 for e, b0 in zip(redges, rest_bend) if bend(co, e) - b0 > math.radians(70))
        if os.environ.get("FOLD_DEBUG"):
            for e, b0 in zip(redges, rest_bend):
                if bend(co, e) - b0 > math.radians(70):
                    print("  FOLD", name, tuple(round(x, 3) for x in rest_co[e[0]]))
        sh = sorted((co[i] - jm[side[i]]).length / max(rest_d[i], 1e-4) for i in reg if rest_d[i] > 0.03)
        poke = 0
        posed = {body.name: (co, nr)}
        for ob in cloth:
            posed[ob.name] = mesh_co(ob)
        for inn, out in pairs:
            ico, inr = posed[inn.name]
            bvh = bvh_of(out, posed[out.name][0])
            for i in covered[(inn.name, out.name)]:
                loc, n, fi, d = bvh.find_nearest(ico[i])
                if loc is not None and d < 0.02 and (loc - ico[i]).dot(inr[i]) < -0.0015:
                    poke += 1
                    if os.environ.get("POKE_DEBUG"):
                        print("  POKE", name, inn.name, out.name, i, tuple(round(x, 3) for x in inn.data.vertices[i].co))
        res[name] = {"squash": round(squash * 100, 2), "minarea": round(min(ratios), 3), "folds": folds,
                     "shrink": round(sh[len(sh) // 20], 3), "poke": poke}
        print("SHOULDER %-12s %s" % (name, res[name]))
    tot = {k: (round(sum(r[k] for r in res.values()), 2) if k in ("squash", "folds", "poke") else
               round(min(r[k] for r in res.values()), 3)) for k in ("squash", "minarea", "folds", "shrink", "poke")}
    print("SHOULDER TOTAL", tot)
    if ARGS:
        with open(ARGS[0], "w") as f:
            json.dump({"poses": res, "total": tot}, f, indent=1)


main()
