"""blender -b /tmp/boy.blend --python art/boy/test_actions.py -- OUTDIR [clip,...]"""
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import posekit, clips, rtools
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
only = argv[1].split(",") if len(argv) > 1 else None
arm = bpy.data.objects["BoyRig"]
rig = posekit.Rig(arm)
rtools.setup_workbench((360, 420))
C = {}
f, L = clips.throw_stand(rig); C["throw_stand"] = (f, L, None)
f, L = clips.throw_crouch(rig); C["throw_crouch"] = (f, L, None)
f, L = clips.cheer(rig); C["cheer"] = (f, L, None)
f, L = clips.oops(rig); C["oops"] = (f, L, None)
for k, f in clips.hammock_clips(rig).items():
    C[k] = (f, 1.0, "lie" if k == "hammock_lie" else "up" if k == "hammock_up" else "flat" if k == "hammock_sleep" else None)
for k, f in clips.towel_clips(rig).items():
    C[k] = (f, 1.0, "lie" if k == "sun_lie" else "up" if k == "sun_up" else "flat" if k == "sun_rest" else None)

N = 6
for name, (fn, L, tip) in C.items():
    if only and name not in only:
        continue
    for j in range(N):
        t = L * j / (N - 1)
        p = fn(t)
        M, over = posekit.apply_pose(rig, p)
        pel = M["pelvis"].translation
        u = t / L
        a = {"lie": u, "up": 1 - u, "flat": 1.0}.get(tip, 0.0)
        if tip:
            arm.matrix_world = Matrix.Translation(pel) @ Matrix.Rotation(-math.pi / 2 * a, 4, "X") @ Matrix.Translation(-pel)
        else:
            arm.matrix_world = Matrix.Identity(4)
        bpy.context.view_layer.update()
        rtools.shoot("%s/%s_%d.png" % (out, name, j), rtools.cam("c", (3.2, -3.6, 1.9), (0, 0, 0.55), 1.8))
        if over > 0.01:
            print("OVER", name, j, round(over, 3))
    arm.matrix_world = Matrix.Identity(4)
