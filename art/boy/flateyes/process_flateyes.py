"""Process flat-eye Mixamo boy GLB for Godot: strip root motion, rename clips, compress textures, write meta.

Do NOT map dig/lift_heavy to sleep or stone-pick — those stay procedural.
"""
import bpy, os, json, shutil
from mathutils import Vector

SRC = "/tmp/tripo/boy_flateyes_rigged.glb"
OUT_DIR = "/workspace/art/boy/flateyes"
OUT_GLB = os.path.join(OUT_DIR, "boy_flateyes.glb")
OUT_META = os.path.join(OUT_DIR, "boy_meta.json")
GAME_GLB = "/workspace/boy/boy.glb"
GAME_META = "/workspace/boy/boy_meta.json"
CONCEPT = "/tmp/tripo/concept_A.jpg"
TEX_DUMP = "/tmp/flateyes/processed_tex"

CLIP_MAP = {
	"idle": "idle",
	"walk": "walk",
	"run": "run",
	"sit": "sit",
	"pitch_baseball": "throw_stand",
	"cheer": "cheer",
	"look_around": "look_around",
	"turn": "turn",
	# Kept for completeness — never wired to sleep / stone-pick.
	"lift_heavy": "lift_heavy",
	"dig": "dig",
}


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	os.makedirs(TEX_DUMP, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=SRC)
	# Drop junk Icosphere (Tripo sometimes embeds one); keep the skinned character mesh.
	for o in list(bpy.data.objects):
		if o.type == "MESH" and ("Ico" in o.name or len(o.data.vertices) < 200):
			print("removed junk", o.name, "verts", len(o.data.vertices))
			bpy.data.objects.remove(o, do_unlink=True)
	arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	mesh = next(o for o in bpy.data.objects if o.type == "MESH")
	print("arm", arm.name, "mesh", mesh.name, "verts", len(mesh.data.vertices), "bones", len(arm.data.bones))
	print("import_fps", bpy.context.scene.render.fps)

	# Compress textures to 1024 JPEG (keep face readable).
	for img in bpy.data.images:
		if img.size[0] < 2:
			continue
		w, h = img.size[0], img.size[1]
		target = 1024 if w >= 1024 else w
		print("resize", img.name, w, h, "->", target)
		if w != target or h != target:
			img.scale(target, target)
		tmp = os.path.join(TEX_DUMP, img.name.replace("/", "_")[:48] + ".jpg")
		img.filepath_raw = tmp
		img.file_format = "JPEG"
		img.save()
		img.pack()

	scene = bpy.context.scene
	# Keep importer FPS (usually 24) so action frame_range / fps = true seconds.
	import_fps = max(scene.render.fps, 1)
	hips_name = "mixamorig:Hips"
	meta_clips = {}

	# Rename actions (gltf importer may keep original names).
	for act in list(bpy.data.actions):
		base = act.name.split(".")[0]
		print("action", act.name, "base", base)

	for old, new in CLIP_MAP.items():
		act = bpy.data.actions.get(old)
		if act is None:
			# Sometimes importer appends .001
			act = bpy.data.actions.get(old + ".001")
		if act is None:
			print("MISSING", old)
			continue
		act.name = new
		loc_curves = {}
		for fc in act.fcurves:
			if hips_name in fc.data_path and "location" in fc.data_path:
				loc_curves[fc.array_index] = fc
		if loc_curves:
			fr0 = int(act.frame_range[0])
			x0 = loc_curves[0].evaluate(fr0) if 0 in loc_curves else 0.0
			y0 = loc_curves[1].evaluate(fr0) if 1 in loc_curves else 0.0
			for idx, fc in loc_curves.items():
				if idx >= 2:
					continue
				for kp in fc.keyframe_points:
					kp.co[1] = x0 if idx == 0 else y0
					kp.handle_left[1] = kp.co[1]
					kp.handle_right[1] = kp.co[1]
			print("stripped root", new, "hips XY", round(x0, 4), round(y0, 4))
		else:
			print(new, "no hips loc curves")
		length = (act.frame_range[1] - act.frame_range[0]) / float(import_fps)
		info = {
			"length": round(length, 4),
			"loop": new in ("idle", "walk", "run", "sit"),
		}
		if new == "walk":
			info.update({"period": round(length, 4), "stride": 0.55, "speed": round(0.55 / max(length, 0.01), 3), "duty": 0.6})
		if new == "run":
			info.update({"period": round(length, 4), "stride": 0.85, "speed": round(0.85 / max(length, 0.01), 3), "duty": 0.45})
		if new == "throw_stand":
			info["t_charge"] = 0.35
			info["t_release"] = 0.55
			info["hand_r"] = []
			info["release"] = [0.12, 0.55, -0.05]
		meta_clips[new] = info

	# Aliases — dig/lift_heavy exist but are NOT used for sleep / stone-pick.
	meta_clips["standing_relax"] = dict(meta_clips["idle"])
	meta_clips["stroll"] = dict(meta_clips["walk"])
	meta_clips["stroll"]["speed"] = meta_clips["walk"]["speed"] * 0.65
	meta_clips["throw_crouch"] = dict(meta_clips["throw_stand"])
	meta_clips["wave"] = dict(meta_clips.get("turn", meta_clips["cheer"]))
	meta_clips["oops"] = dict(meta_clips["cheer"])
	meta_clips["jump"] = dict(meta_clips["idle"])
	meta_clips["jump"]["loop"] = False
	for alias in (
		"sun_sit", "sun_lie", "sun_rest", "sun_up", "sun_stand",
		"hammock_sit", "hammock_lie", "hammock_sleep", "hammock_up", "hammock_stand",
		"seat_sit", "seat_rest", "seat_lie", "seat_nap", "seat_up", "seat_stand",
	):
		meta_clips[alias] = dict(meta_clips["sit"])
		if "lie" in alias or "sleep" in alias or "nap" in alias:
			meta_clips[alias]["pelvis"] = [[0.0, 0.15, 0.12]]
		else:
			meta_clips[alias]["pelvis"] = [[0.0, 0.0, 0.25]]

	for pb in arm.pose.bones:
		pb.matrix_basis.identity()
	bpy.context.view_layer.update()
	deps = bpy.context.evaluated_depsgraph_get()
	me = mesh.evaluated_get(deps)
	to_mesh = me.to_mesh()
	wzs = [(me.matrix_world @ v.co).z for v in to_mesh.vertices]
	zmin = min(wzs)
	zmax = max(wzs)
	me.to_mesh_clear()
	height = zmax - zmin
	ground = zmin
	print("measured height", height, "ground", ground)

	def bone_head(name):
		b = arm.data.bones.get(name)
		return list(b.head_local) if b else [0, 0, 0]

	rest = {
		"pelvis": bone_head("mixamorig:Hips"),
		"head": bone_head("mixamorig:Head"),
		"hand_r": bone_head("mixamorig:RightHand"),
	}
	meta_clips["throw_stand"]["release"] = rest["hand_r"]
	meta_clips["throw_crouch"]["release"] = rest["hand_r"]

	meta = {
		"fps": 30,
		"ground": round(ground, 4),
		"height": round(height, 4),
		"clips": meta_clips,
		"rest": rest,
		"stone_local": [0.02, 0.06, 0.0],
		"eyes": [],
		"face_rect": [-0.08, -0.08, 0.16, 0.18],
		"tripo": True,
		"bones": "mixamo",
		"flat_eyes": True,
		"source": "boy_flateyes_rigged.glb",
	}

	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	mesh.select_set(True)
	bpy.context.view_layer.objects.active = arm
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
		export_jpeg_quality=82, export_rest_position_armature=True,
	)
	shutil.copy2(OUT_GLB, GAME_GLB)
	with open(OUT_META, "w") as f:
		json.dump(meta, f, indent=2)
	with open(GAME_META, "w") as f:
		json.dump(meta, f, indent=2)
	if os.path.isfile(CONCEPT):
		shutil.copy2(CONCEPT, os.path.join(OUT_DIR, "concept_A.jpg"))
		shutil.copy2(CONCEPT, "/workspace/art/boy/concept_A.jpg")
	print("EXPORTED", OUT_GLB, "bytes", os.path.getsize(OUT_GLB))
	print("height", height, "ground", ground, "clips", sorted(meta_clips.keys()))


if __name__ == "__main__":
	main()
