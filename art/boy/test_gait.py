"""blender -b /tmp/boy.blend --python art/boy/test_gait.py -- OUTDIR : renders gait phases"""
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import posekit, clips, rtools
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1]
rig = posekit.Rig(bpy.data.objects["BoyRig"])
rtools.setup_workbench((400, 560))
walk = clips.Gait(rig, *clips.WALK)
run = clips.Gait(rig, *clips.RUN, run=True)
idle = clips.idle(rig)
shots = []
for name, g in (("walk", walk), ("run", run)):
    for i in range(8):
        t = g.T * i / 8
        M, over = posekit.apply_pose(rig, g.pose(t))
        bpy.context.view_layer.update()
        rtools.shoot("%s/%s_%d.png" % (out, name, i), rtools.cam("cs", (6, 0, 0.75), (0, 0, 0.75), 1.7))
        print("OVER", name, i, round(over, 3))
posekit.apply_pose(rig, idle(0.7))
bpy.context.view_layer.update()
rtools.shoot(out + "/idle_f.png", rtools.cam("cf", (0, -6, 0.75), (0, 0, 0.75), 1.7))
rtools.shoot(out + "/idle_s.png", rtools.cam("cs", (6, 0, 0.75), (0, 0, 0.75), 1.7))
posekit.apply_pose(rig, walk.pose(0.1))
bpy.context.view_layer.update()
rtools.shoot(out + "/walk_f.png", rtools.cam("cf", (0, -6, 0.75), (0, 0, 0.75), 1.7))
