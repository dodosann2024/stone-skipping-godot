"""Process Tripo boy GLB for Godot: drop junk, strip root motion, rename clips, compress textures."""
import bpy, bmesh, os, json, math
from mathutils import Vector, Quaternion, Matrix

SRC = "/tmp/tripo/boy_tripo_rigged_10anims.glb"
OUT_DIR = "/workspace/art/boy/tripo"
OUT_GLB = os.path.join(OUT_DIR, "boy_tripo.glb")
OUT_META = os.path.join(OUT_DIR, "boy_meta.json")
GAME_GLB = "/workspace/boy/boy.glb"
GAME_META = "/workspace/boy/boy_meta.json"
CONCEPT = "/tmp/tripo/concept_A.jpg"

CLIP_MAP = {
    "idle.001": "idle",
    "standing_relax.001": "standing_relax",
    "walk.001": "walk",
    "run.001": "run",
    "pitch_baseball.001": "throw_stand",
    "sit.001": "sit",
    "cheer.001": "cheer",
    "wave_goodbye_01.001": "wave",
    "look_around.001": "look_around",
    "jump.001": "jump",
}

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    # delete junk icosphere
    for o in list(bpy.data.objects):
        if o.type == "MESH" and "Ico" in o.name:
            name = o.name
            bpy.data.objects.remove(o, do_unlink=True)
            print("removed", name)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    print("arm", arm.name, "mesh", mesh.name)

    # compress textures to 1024 JPEG
    for img in bpy.data.images:
        if img.size[0] < 2:
            continue
        print("resize", img.name, img.size[:], "-> 1024")
        img.scale(1024, 1024)
        # force packed jpeg-ish by saving temp
        tmp = "/tmp/tripo/%s.jpg" % img.name.replace("/", "_")[:40]
        img.filepath_raw = tmp
        img.file_format = "JPEG"
        img.save()
        img.pack()

    # rename + strip root motion on hips
    scene = bpy.context.scene
    scene.render.fps = 30
    hips_name = "mixamorig:Hips"
    meta_clips = {}
    for old, new in CLIP_MAP.items():
        act = bpy.data.actions.get(old)
        if not act:
            print("MISSING", old)
            continue
        act.name = new
        # find location fcurves for hips
        loc_curves = {}
        for fc in act.fcurves:
            if hips_name in fc.data_path and "location" in fc.data_path:
                loc_curves[fc.array_index] = fc
        if not loc_curves:
            print(new, "no hips loc curves")
        else:
            # rest hips XY from frame start
            fr0 = int(act.frame_range[0])
            fr1 = int(act.frame_range[1])
            x0 = loc_curves[0].evaluate(fr0) if 0 in loc_curves else 0.0
            y0 = loc_curves[1].evaluate(fr0) if 1 in loc_curves else 0.0
            # zero horizontal drift: set all keys X,Y to start values
            for idx, fc in loc_curves.items():
                if idx >= 2:
                    continue  # keep Z (height bob)
                for kp in fc.keyframe_points:
                    kp.co[1] = x0 if idx == 0 else y0
                    kp.handle_left[1] = kp.co[1]
                    kp.handle_right[1] = kp.co[1]
            print("stripped root", new, "hips XY locked to", round(x0,4), round(y0,4))
        length = (act.frame_range[1] - act.frame_range[0]) / scene.render.fps
        info = {"length": round(length, 4), "loop": new in ("idle", "standing_relax", "walk", "run", "sit")}
        if new == "walk":
            info.update({"period": round(length, 4), "stride": 0.55, "speed": round(0.55 / max(length, 0.01), 3), "duty": 0.6})
        if new == "run":
            info.update({"period": round(length, 4), "stride": 0.85, "speed": round(0.85 / max(length, 0.01), 3), "duty": 0.45})
        if new == "throw_stand":
            # pitch_baseball ~92 frames; release near mid-late windup (~0.55 of clip)
            info["t_charge"] = 0.35
            info["t_release"] = 0.55
            info["hand_r"] = []
            info["release"] = [0.12, 0.55, -0.05]  # approx palm in model space (filled later)
        meta_clips[new] = info

    # also alias stroll -> walk, throw_crouch -> throw_stand, sun/hammock/seat clips -> sit
    meta_clips["stroll"] = dict(meta_clips["walk"])
    meta_clips["stroll"]["speed"] = meta_clips["walk"]["speed"] * 0.65
    meta_clips["throw_crouch"] = dict(meta_clips["throw_stand"])
    for alias in ("sun_sit", "sun_lie", "sun_rest", "sun_up", "sun_stand",
                  "hammock_sit", "hammock_lie", "hammock_sleep", "hammock_up", "hammock_stand",
                  "seat_sit", "seat_rest", "seat_lie", "seat_nap", "seat_up", "seat_stand"):
        meta_clips[alias] = dict(meta_clips["sit"])
        # pelvis track: approximate offsets for activity placement (metres, Blender Z-up)
        if "lie" in alias or "sleep" in alias or "nap" in alias:
            meta_clips[alias]["pelvis"] = [[0.0, 0.15, 0.12]]
        else:
            meta_clips[alias]["pelvis"] = [[0.0, 0.0, 0.25]]
    meta_clips["oops"] = dict(meta_clips.get("wave", meta_clips["cheer"]))

    # measure height / ground / rest bones
    # apply rest pose
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    bb = [mesh.matrix_world @ Vector(c) for c in mesh.bound_box]
    zmin = min(v.z for v in bb)
    zmax = max(v.z for v in bb)
    height = zmax - zmin
    ground = zmin
    def bone_head(name):
        b = arm.data.bones.get(name)
        return list(b.head_local) if b else [0,0,0]
    rest = {
        "pelvis": bone_head("mixamorig:Hips"),
        "head": bone_head("mixamorig:Head"),
        "hand_r": bone_head("mixamorig:RightHand"),
    }
    # stone_local approx in RightHand frame
    stone_local = [0.02, 0.06, 0.0]
    meta_clips["throw_stand"]["release"] = rest["hand_r"]
    meta_clips["throw_crouch"]["release"] = rest["hand_r"]

    meta = {
        "fps": 30,
        "ground": round(ground, 4),
        "height": round(height, 4),
        "clips": meta_clips,
        "rest": rest,
        "stone_local": stone_local,
        "eyes": [],
        "face_rect": [-0.08, -0.08, 0.16, 0.18],
        "tripo": True,
        "bones": "mixamo",
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    # select armature + mesh for export
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm
    # clear leftover actions not in map
    keep = set(CLIP_MAP.values())
    for a in list(bpy.data.actions):
        if a.name not in keep:
            bpy.data.actions.remove(a)
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB, export_format="GLB", use_selection=True,
        export_apply=False, export_animations=True, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_frame_step=1, export_skins=True,
        export_yup=True, export_texcoords=True, export_normals=True,
        export_materials="EXPORT", export_image_format="JPEG",
        export_jpeg_quality=80, export_rest_position_armature=True,
    )
    import shutil
    shutil.copy2(OUT_GLB, GAME_GLB)
    with open(OUT_META, "w") as f:
        json.dump(meta, f, indent=2)
    with open(GAME_META, "w") as f:
        json.dump(meta, f, indent=2)
    # concept
    shutil.copy2(CONCEPT, os.path.join(OUT_DIR, "concept_A.jpg"))
    shutil.copy2(CONCEPT, "/workspace/art/boy/concept_A.jpg")
    print("EXPORTED", OUT_GLB, "bytes", os.path.getsize(OUT_GLB))
    print("height", height, "ground", ground, "clips", list(meta_clips.keys()))

if __name__ == "__main__":
    main()
