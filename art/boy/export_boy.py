"""Join the boy, bake AO + all clips, export boy/boy.glb and boy/boy_meta.json for Godot."""
import bpy, json, os, math
import posekit, clips
from mathutils import Vector

FPS = 30
LOOPS = {"idle", "walk", "run", "hammock_sleep", "sun_rest", "seat_rest", "seat_nap"}
RIGID = ("Hat", "Glasses", "Stone")      # bone-parented props (BoneAttachment3D in Godot)


def join_parts(rig):
    body = bpy.data.objects["Body"]
    parts = [o for o in bpy.data.objects if o.type == "MESH" and o.name not in RIGID and o != body]
    if body.data.uv_layers:
        body.data.uv_layers[0].name = "UVMap"
    for o in parts:
        me = o.data
        while len(me.uv_layers) < 2:
            me.uv_layers.new()
        me.uv_layers[0].name = "UVMap"
        me.uv_layers[1].name = "Face"
        for d in me.uv_layers[1].data:
            d.uv = (5.0, 5.0)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts + [body]:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "BoyMesh"
    body.data.name = "BoyMesh"
    return body


def bake_ao(objs):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    sc.cycles.device = "CPU"
    sc.world = sc.world or bpy.data.worlds.new("W")
    sc.world.light_settings.distance = 0.25
    for o in objs:
        me = o.data
        if "AO" not in me.color_attributes:
            me.color_attributes.new("AO", "BYTE_COLOR", "POINT")
        me.color_attributes.active_color = me.color_attributes["AO"]
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")


def face_mask(body, rig):
    """AO lives in the colour's red channel; green = 1 on the face. UV2 becomes one continuous
    front projection so the shader's fwidth() has no seams"""
    me = body.data
    hz = rig.data.bones["head"].head_local.z
    uv2 = me.uv_layers["Face"]
    face = set(l.vertex_index for l in me.loops if uv2.data[l.index].uv.x < 4.0)
    col = me.color_attributes["AO"]
    for i, d in enumerate(col.data):
        c = d.color
        d.color = (c[0], 1.0 if i in face else 0.0, c[2], 1.0)
    for l in me.loops:
        co = me.vertices[l.vertex_index].co
        uv2.data[l.index].uv = (co.x, co.z - hz)


def bake_clips(rig_obj, meta):
    rig = posekit.Rig(rig_obj)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start = 0
    acts = {}
    walk = clips.Gait(rig, 1.0, 1.0, 0.62)
    run = clips.Gait(rig, 0.68, 2.04, 0.36, run=True)
    todo = [
        ("idle", clips.idle(rig), 4.0),
        ("walk", walk.pose, walk.T),
        ("run", run.pose, run.T),
    ]
    f, L = clips.throw_stand(rig); todo.append(("throw_stand", f, L))
    f, L = clips.throw_crouch(rig); todo.append(("throw_crouch", f, L))
    f, L = clips.cheer(rig); todo.append(("cheer", f, L))
    f, L = clips.oops(rig); todo.append(("oops", f, L))
    for k, f in clips.hammock_clips(rig).items():
        todo.append((k, f, 4.0 if k in LOOPS else 1.0))
    for k, f in clips.towel_clips(rig).items():
        todo.append((k, f, 4.0 if k in LOOPS else 1.0))
    for k, f in clips.seat_clips(rig).items():
        todo.append((k, f, 4.0 if k in LOOPS else 1.0))
    meta["clips"] = {}
    for name, fn, L in todo:
        frames = int(round(L * FPS))
        act, info = posekit.bake(rig, name, fn, frames, FPS, loop=name in LOOPS)
        acts[name] = act
        m = {"length": frames / FPS, "loop": name in LOOPS}
        if name in ("walk", "run"):
            g = walk if name == "walk" else run
            m.update({"period": g.T, "stride": g.S, "speed": g.S / g.T, "duty": g.duty})
        if name.startswith(("hammock", "sun", "seat")):
            m["pelvis"] = [list(p) for p in info["pelvis"]]
        if name.startswith("throw"):
            fr = int(round(clips.T_RELEASE * FPS))
            m["t_charge"] = clips.T_CHARGE
            m["t_release"] = clips.T_RELEASE
            m["hand_r"] = [list(p) for p in info["hand_r"]]
            # stone sits in the palm: a bit along the hand from the wrist
            m["release"] = list(info["hand_r"][fr])
        meta["clips"][name] = m
    return acts


def export(rig_obj, out_dir):
    meta = {"fps": FPS, "ground": posekit.GROUND}
    body = join_parts(rig_obj)
    hat = bpy.data.objects["Hat"]
    props = [bpy.data.objects[n] for n in RIGID]
    bake_ao([body, hat])
    face_mask(body, rig_obj)
    acts = bake_clips(rig_obj, meta)
    # stone offset from the hand bone (palm centre), in the hand bone's rest frame
    hb = rig_obj.data.bones["hand_r"]
    mid = rig_obj.data.bones["middle_01_r"]
    palm = (Vector(hb.head_local) * 0.4 + Vector(mid.head_local) * 0.6)
    meta["stone_local"] = list(hb.matrix_local.inverted() @ palm)
    meta["eyes"] = [list(e) for e in body["eyes_uv"]]
    meta["height"] = max(v.co.z for v in body.data.vertices) - posekit.GROUND
    for b in ("pelvis", "head", "hand_r"):
        meta.setdefault("rest", {})[b] = list(rig_obj.data.bones[b].head_local)
    os.makedirs(out_dir, exist_ok=True)
    rig_obj.animation_data_create()
    rig_obj.animation_data.action = None
    for pb in rig_obj.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [rig_obj, body] + props:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig_obj
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out_dir, "boy.glb"), export_format="GLB", use_selection=True,
        export_apply=True, export_animations=True, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_frame_step=1, export_skins=True, export_all_influences=False,
        export_morph=False, export_yup=True, export_texcoords=True, export_normals=True, export_tangents=False,
        export_vertex_color="ACTIVE", export_materials="EXPORT", export_image_format="NONE",
        export_optimize_animation_size=False, export_anim_slide_to_zero=False, export_def_bones=False,
        export_rest_position_armature=True, export_extras=False,
    )
    with open(os.path.join(out_dir, "boy_meta.json"), "w") as f:
        json.dump(meta, f, indent=0, separators=(",", ":"))
    print("EXPORTED", out_dir, "clips", len(acts), "tris", sum(len(p.vertices) - 2 for p in body.data.polygons) + sum(len(p.vertices) - 2 for p in hat.data.polygons))
