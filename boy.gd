class_name Boy
extends Node3D
## v22 Tripo boy: AI-generated Mixamo-rigged kid (boy/boy.glb from art/boy/tripo/).
## Same public API as the old procedural Boy so main.gd / selftest / sim keep working.
## Straw hat is baked into the Tripo mesh (never split). An invisible HatProbe proxy
## sits on the Head bone. Lying poses tip the head so the brim rests on the support.
## Face is baked (open eyes). Sleep uses a forearm-over-eyes nap pose — no blink,
## no closed-eye albedo (Tripo eye shells can't read as lids without a new model).

signal released
signal footstep(side: int, running: bool)
signal foot_flat(side: int)

# ~1.35× so seated Mixamo hips sit near Island.SEAT_TOP (0.35 m) and the kid reads ~4 heads tall
const SCALE := 1.35
const MODEL := preload("res://boy/boy.glb")
const META := "res://boy/boy_meta.json"
const T_RELEASE := 0.55
const RUN_FROM := 1.35
const RUN_TO := 2.2
const SIT_HIPS_Y := 0.248  # unscaled Mixamo sit hips (see process_tripo / smoke)

# Mixamo bone names (Godot converts ':' -> '_')
const B_HIPS := "mixamorig_Hips"
const B_HEAD := "mixamorig_Head"
const B_HAND_R := "mixamorig_RightHand"
const B_HAND_L := "mixamorig_LeftHand"
const B_FOOT := ["mixamorig_LeftFoot", "mixamorig_RightFoot"]
const B_TOE := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const TWIST_BONES := ["mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head"]
const TWIST_SHARE := [0.15, 0.25, 0.25, 0.35]

var parts := {}
var anim := "idle"
var anim_t := 0.0
var stance := "stand"
var wading := false
var move_speed := 0.0
var power := 0.0
var throw_power := 0.0
var react_kind := ""
var did_release := false
var release_stand := Vector3.ZERO
var release_crouch := Vector3.ZERO
var release_local: Vector3:
	get:
		return release_crouch if stance == "crouch" else release_stand

var meta: Dictionary
var clips: Dictionary
var model: Node3D
var skel: Skeleton3D
var tree: AnimationTree
var bt: AnimationNodeBlendTree
var ap: AnimationPlayer
var hat: MeshInstance3D
var glasses: Node3D
var stone: MeshInstance3D
var blob: MeshInstance3D
var face_mat: ShaderMaterial
var head_mi: MeshInstance3D
var hair_mat: ShaderMaterial
var hair_mi: MeshInstance3D
var cloth_mats: Array[ShaderMaterial] = []

var hat_s := 0.0
var hat_hold := 0.0
var hat_side := "r"
var hat_band_c := Vector3(0, 0.02, 0)
var hat_head_xf := Transform3D.IDENTITY
var hat_face_xf := Transform3D.IDENTITY
## Always "head" — baked Tripo hat never detaches. Kept for selftest / main API.
var hat_mode := "head"
## Legacy sand spot (unused; hat stays on the head). Kept so main.gd can still assign it.
var hat_beside_world := Vector3.ZERO
## Bind-pose local verts of the baked straw crown/brim (for lie penetration).
var _hat_skin_idxs: PackedInt32Array = PackedInt32Array()

var t := 0.0
var t_idle := 0.0
var phase := 0.0
var move_w := 0.0
var run_k := 0.0
var walk_k := 1.0
var speed_s := 0.0
var prev_pos := Vector3.ZERO
var has_prev := false
var slot_clip: Array[String] = ["", ""]
var slot_t: Array[float] = [0.0, 0.0]
var cur_slot := 0
var ab_w := 0.0
var ab_rate := 10.0
var act_w := 0.0
var act_target := 0.0
var act_rate := 6.0
var stopping := false
var act_frames := 0
var pre_act: Array = []
var prev_sit := 0.0
var prev_lie := 0.0
var blink_timer := 2.5
var blink_t := -1.0
var expr := "smile"
var rng := RandomNumberGenerator.new()
var frozen := false
var model_base := Vector3.ZERO
var pivoting := false
var turn_ahead := 0.0
var turn_lean := 0.0
var aim_twist := 0.0
var steps_taken := 0
var spot_steps := 0
var lead_dt := 0.016
var lead_y := [0.0, 0.0, 0.0, 0.0]
var plant_lag := 0.0
var spin := false
var hip_shift := Vector3.ZERO
var last_dt := 0.016
var plant_prev_yaw := 0.0
var turn_w := 0.0
var contacts: Array = []
var legs: Array = []
var gait_tab := {}
var morph_idx := {}
var morph := {}
var lock_enabled := true  # stub: Tripo has no plant IK; walk_metrics may toggle this
var _hat_attach: BoneAttachment3D
var _hand_attach: BoneAttachment3D
var _prev_phase_side := -1
var was_pivoting := false
var spot_clock := 0.0
var spot_emitted := 0
var pivot_grace := 0.0
var lie_settle := 0.0  # local model drop while sit-as-lie (main pins pelvis via global_transform)
var act_kind := ""
var act_lie_k := 0.0
var act_tt := 0.0
var face_fill: OmniLight3D
var _night_rim: OmniLight3D
var _night_body: OmniLight3D
var _face_fill_day_energy := 0.35
var _boy_mat: StandardMaterial3D
var _boy_albedo_day := Color(1.08, 0.98, 0.92, 1.0)
var _boy_albedo_tex_day: Texture2D
var _boy_albedo_tex_sleep: Texture2D
var _eyes_closed_tex := false  # always false — closed albedo abandoned for Tripo shells
var _eyelid_l: MeshInstance3D
var _eyelid_r: MeshInstance3D
var _mouth: MeshInstance3D
var _walk_bob := 0.0
var _settle_left := 0.0
## When set, lounger pose plants heels/knees/thighs on this seat plane after the hips pitch.
var lie_foot_plant := false
var lie_foot_plane_point := Vector3.ZERO
var lie_foot_plane_normal := Vector3.UP
var lie_foot_plant_gap := 0.015


func _ready() -> void:
	rng.seed = 7
	process_priority = 10
	meta = JSON.parse_string(FileAccess.get_file_as_string(META))
	clips = meta["clips"]
	model = MODEL.instantiate()
	# Tripo/Mixamo faces +Z in glTF Y-up; game boy faces -Z like the old model
	model.rotation.y = PI
	model.scale = Vector3.ONE * SCALE
	var ground := float(meta.get("ground", 0.0))
	model.position.y = -ground * SCALE
	model_base = model.position
	add_child(model)
	skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_force_loops()
	_patch_ergonomic_sit_anim()
	_setup_parts()
	_setup_tree()
	_build_blob()
	_build_stone()
	_build_hat_proxy()
	_build_glasses_stub()
	_build_face_fill()
	_build_face_expr()
	_tune_boy_material()
	set_face_expr("smile")
	release_stand = _probe_release("throw_stand")
	# crouch: clearly lower release so water entry is flatter than standing
	release_crouch = release_stand + Vector3(0.02, -0.14 * SCALE, 0.04)
	_apply_mixer()


func _force_loops() -> void:
	if ap == null:
		return
	for n in ["idle", "standing_relax", "walk", "run", "sit", "stroll"]:
		if ap.has_animation(n):
			var a: Animation = ap.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR
	# stroll may be missing — AnimationTree uses walk for stroll seek


## Rewrite Mixamo sit leg keys to an ergonomic L-sit. Compatibility skinning only follows
## AnimationTree/Player — set_bone_pose_rotation alone leaves the mesh standing.
func _patch_ergonomic_sit_anim() -> void:
	if ap == null or not ap.has_animation("sit"):
		return
	var sit: Animation = ap.get_animation("sit")
	var targets := {
		"mixamorig_LeftUpLeg": Quaternion.from_euler(Vector3(-1.30, 0.05, 0.08)),
		"mixamorig_RightUpLeg": Quaternion.from_euler(Vector3(-1.30, -0.05, -0.08)),
		"mixamorig_LeftLeg": Quaternion.from_euler(Vector3(-1.90, 0.0, 0.0)),
		"mixamorig_RightLeg": Quaternion.from_euler(Vector3(-1.90, 0.0, 0.0)),
		"mixamorig_LeftFoot": Quaternion.from_euler(Vector3(0.25, 0.0, 0.05)),
		"mixamorig_RightFoot": Quaternion.from_euler(Vector3(0.25, 0.0, -0.05)),
		"mixamorig_Spine": Quaternion.from_euler(Vector3(-0.08, 0.0, 0.0)),
		"mixamorig_Spine1": Quaternion.from_euler(Vector3(-0.05, 0.0, 0.0)),
		"mixamorig_LeftArm": Quaternion.from_euler(Vector3(0.20, 0.40, -0.60)),
		"mixamorig_RightArm": Quaternion.from_euler(Vector3(0.20, -0.40, 0.60)),
		"mixamorig_LeftForeArm": Quaternion.from_euler(Vector3(-0.40, 0.0, 0.0)),
		"mixamorig_RightForeArm": Quaternion.from_euler(Vector3(-0.40, 0.0, 0.0)),
	}
	for t in sit.get_track_count():
		if sit.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var p := str(sit.track_get_path(t))
		for bone in targets.keys():
			if p.ends_with(":" + bone):
				for k in sit.track_get_key_count(t):
					sit.track_set_key_value(t, k, targets[bone])
				break


func _setup_parts() -> void:
	var head_att := BoneAttachment3D.new()
	head_att.name = "HeadAttach"
	head_att.bone_name = B_HEAD
	skel.add_child(head_att)
	parts["head"] = head_att
	var pel_att := BoneAttachment3D.new()
	pel_att.name = "PelvisAttach"
	pel_att.bone_name = B_HIPS
	skel.add_child(pel_att)
	parts["pelvis"] = pel_att
	_hand_attach = BoneAttachment3D.new()
	_hand_attach.name = "HandRAttach"
	_hand_attach.bone_name = B_HAND_R
	skel.add_child(_hand_attach)
	# foot contacts for gait stubs
	for i in 2:
		var fb := skel.find_bone(B_FOOT[i])
		var tb := skel.find_bone(B_TOE[i])
		contacts.append([fb, Vector3.ZERO, tb, Vector3.ZERO])
		legs.append([skel.find_bone("mixamorig_LeftUpLeg" if i == 0 else "mixamorig_RightUpLeg"),
			skel.find_bone("mixamorig_LeftLeg" if i == 0 else "mixamorig_RightLeg"), fb, tb])


func _anim_node(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n


func _setup_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimTree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	tree.active = true
	tree.callback_mode_process = AnimationTree.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	bt = AnimationNodeBlendTree.new()
	tree.tree_root = bt
	# locomotion: idle <-> (walk <-> run)
	bt.add_node("idle", _anim_node("idle"), Vector2(0, 0))
	bt.add_node("walk", _anim_node("walk"), Vector2(0, 80))
	bt.add_node("run", _anim_node("run"), Vector2(0, 160))
	bt.add_node("idle_s", AnimationNodeTimeSeek.new(), Vector2(120, 0))
	bt.add_node("walk_s", AnimationNodeTimeSeek.new(), Vector2(120, 80))
	bt.add_node("run_s", AnimationNodeTimeSeek.new(), Vector2(120, 160))
	bt.connect_node("idle_s", 0, "idle")
	bt.connect_node("walk_s", 0, "walk")
	bt.connect_node("run_s", 0, "run")
	var wr := AnimationNodeBlend2.new()
	bt.add_node("wr", wr, Vector2(260, 120))
	bt.connect_node("wr", 0, "walk_s")
	bt.connect_node("wr", 1, "run_s")
	var move := AnimationNodeBlend2.new()
	bt.add_node("move", move, Vector2(400, 40))
	bt.connect_node("move", 0, "idle_s")
	bt.connect_node("move", 1, "wr")
	# action slots a/b
	bt.add_node("a", _anim_node("idle"), Vector2(0, 280))
	bt.add_node("b", _anim_node("idle"), Vector2(0, 360))
	bt.add_node("a_s", AnimationNodeTimeSeek.new(), Vector2(120, 280))
	bt.add_node("b_s", AnimationNodeTimeSeek.new(), Vector2(120, 360))
	bt.connect_node("a_s", 0, "a")
	bt.connect_node("b_s", 0, "b")
	var ab := AnimationNodeBlend2.new()
	bt.add_node("ab", ab, Vector2(260, 320))
	bt.connect_node("ab", 0, "a_s")
	bt.connect_node("ab", 1, "b_s")
	var act := AnimationNodeBlend2.new()
	bt.add_node("act", act, Vector2(520, 160))
	bt.connect_node("act", 0, "move")
	bt.connect_node("act", 1, "ab")
	bt.connect_node("output", 0, "act")
	# stroll alias: reuse walk node seek (no separate stroll clip required)
	bt.add_node("stroll", _anim_node("walk"), Vector2(-120, 80))
	bt.add_node("stroll_s", AnimationNodeTimeSeek.new(), Vector2(-120, 140))
	bt.connect_node("stroll_s", 0, "stroll")


func _build_blob() -> void:
	blob = MeshInstance3D.new()
	blob.name = "Blob"
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	blob.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	blob.material_override = m
	blob.rotation.x = -PI * 0.5
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blob)


func _build_stone() -> void:
	stone = MeshInstance3D.new()
	stone.name = "Stone"
	var sm := SphereMesh.new()
	sm.radius = 0.028
	sm.height = 0.05
	stone.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.56, 0.58)
	stone.material_override = mat
	_hand_attach.add_child(stone)
	stone.position = Vector3(0.02, 0.07, 0.01)


func _build_hat_proxy() -> void:
	# Tiny invisible mesh so HatProbe can sample verts; hat is baked into the body.
	_hat_attach = BoneAttachment3D.new()
	_hat_attach.name = "HatAttach"
	_hat_attach.bone_name = B_HEAD
	skel.add_child(_hat_attach)
	hat = MeshInstance3D.new()
	hat.name = "Hat"
	var bm := SphereMesh.new()
	bm.radius = 0.04
	bm.height = 0.06
	hat.mesh = bm
	hat.visible = false
	hat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hat_attach.add_child(hat)
	hat.position = Vector3(0, 0.08, 0)
	hat_mode = "head"


## API stub: baked hat never leaves the head. Modes other than "head" are ignored.
func set_hat_mode(mode: String, beside_world: Vector3 = Vector3.ZERO) -> void:
	hat_mode = "head"
	if beside_world != Vector3.ZERO:
		hat_beside_world = beside_world
	if hat and is_instance_valid(hat):
		hat.visible = false


## API stub: keep the baked hat on the Head bone for the whole sit↔lie window.
func sync_hat_lie(_kind: String, _lie_k: float) -> void:
	hat_mode = "head"
	if hat and is_instance_valid(hat):
		hat.visible = false


func _build_glasses_stub() -> void:
	glasses = Node3D.new()
	glasses.name = "Glasses"
	glasses.visible = false
	parts["head"].add_child(glasses)


func _build_face_fill() -> void:
	# Gentle under-brim fill only on the boy mesh (layer 2). No emission — keep concept_A saturation.
	face_fill = OmniLight3D.new()
	face_fill.name = "FaceFill"
	face_fill.light_color = Color(1.0, 0.92, 0.78)
	face_fill.light_energy = 0.35
	face_fill.omni_range = 0.4
	face_fill.omni_attenuation = 1.4
	face_fill.shadow_enabled = false
	face_fill.light_specular = 0.0
	# Boy mesh only (layer 2) — lighting the world made a moving hotspot on sand/seats.
	face_fill.light_cull_mask = 1 << 1
	parts["head"].add_child(face_fill)
	face_fill.position = Vector3(0.0, -0.02, -0.1)
	# Cool moonlight rim — only on at night, opposite the fill so edges read without flattening him.
	_night_rim = OmniLight3D.new()
	_night_rim.name = "NightRim"
	_night_rim.light_color = Color(0.55, 0.68, 0.98)
	_night_rim.light_energy = 0.0
	_night_rim.omni_range = 0.75
	_night_rim.omni_attenuation = 1.2
	_night_rim.shadow_enabled = false
	_night_rim.light_specular = 0.08
	_night_rim.light_cull_mask = 1 << 1
	parts["head"].add_child(_night_rim)
	_night_rim.position = Vector3(0.0, 0.04, 0.12)
	# Soft torso fill at night so vest/shorts match the moonlit ground (head fill alone leaves the body black).
	_night_body = OmniLight3D.new()
	_night_body.name = "NightBody"
	_night_body.light_color = Color(0.70, 0.80, 1.0)
	_night_body.light_energy = 0.0
	_night_body.omni_range = 1.4
	_night_body.omni_attenuation = 0.85
	_night_body.shadow_enabled = false
	_night_body.light_specular = 0.0
	_night_body.light_cull_mask = 1 << 1
	if parts.has("pelvis"):
		parts["pelvis"].add_child(_night_body)
		_night_body.position = Vector3(0.0, 0.12, -0.08)
	else:
		add_child(_night_body)
		_night_body.position = Vector3(0.0, 0.55, -0.1)


## Blend the character-only fill with the world night look. k=0 day, k=1 full night.
## moon_dir: world direction toward the moon disk (sun.global_basis.z); used to place the rim.
func set_night_k(k: float, moon_dir: Vector3 = Vector3.ZERO) -> void:
	k = clampf(k, 0.0, 1.0)
	if face_fill:
		# Day: warm under-brim fill. Night: cool body fill so seats/hammock match moonlit ground
		# (v23 balance — boy luminance tracks the scene, not a black silhouette).
		face_fill.light_color = Color(1.0, 0.92, 0.78).lerp(Color(0.78, 0.86, 1.0), k)
		face_fill.light_energy = lerpf(_face_fill_day_energy, 1.35, k)
		face_fill.omni_range = lerpf(0.4, 1.6, k)
		face_fill.omni_attenuation = lerpf(1.4, 0.7, k)
		# Chest/torso fill (not just under the brim) so vest/shorts read at night.
		face_fill.position = Vector3(0.0, -0.04, -0.16).lerp(Vector3(0.0, -0.12, -0.22), k)
	if _night_rim:
		_night_rim.light_color = Color(0.55, 0.68, 0.98)
		_night_rim.light_energy = lerpf(0.0, 0.95, k)
		_night_rim.omni_range = lerpf(0.55, 1.6, k)
		var local_off := Vector3(0.0, 0.04, 0.14)
		if moon_dir.length_squared() > 0.01 and parts.has("head") and parts["head"] is Node3D:
			var head := parts["head"] as Node3D
			var world_off: Vector3 = moon_dir.normalized() * 0.18 + Vector3(0, 0.04, 0)
			local_off = head.global_transform.basis.inverse() * world_off
			if local_off.length() < 0.06:
				local_off = Vector3(0.0, 0.04, 0.14)
			else:
				local_off = local_off.normalized() * 0.18
		_night_rim.position = local_off
	if _night_body:
		_night_body.light_energy = lerpf(0.0, 1.15, k)
		_night_body.omni_range = lerpf(0.8, 1.8, k)
		_night_body.light_color = Color(0.70, 0.80, 1.0)
	# Keep Tripo textures readable against moonlit sand (not a black silhouette).
	if _boy_mat:
		_boy_mat.albedo_color = _boy_albedo_day.lerp(Color(1.05, 1.05, 1.1, 1.0), k)
		_boy_mat.metallic_specular = lerpf(0.2, 0.06, k)
		_boy_mat.roughness = lerpf(0.78, 0.86, k)
		_boy_mat.emission_enabled = false
		_boy_mat.emission_energy_multiplier = 0.0
		_boy_mat.emission = Color(0, 0, 0, 1)


func _tune_boy_material() -> void:
	# Tripo embeds metallic=1 which blacks out the face under the brim. Drop metal only —
	# no emission (that washed the vest/skin/hat into pastels). Stay fully opaque.
	# Full PBR albedo texture preserved — never split or recolor the baked hat/hair.
	if skel == null:
		return
	for c in skel.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		var src: Material = mi.get_active_material(0)
		if src == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			src = mi.mesh.surface_get_material(0)
		if src == null:
			continue
		var mat := src.duplicate() as StandardMaterial3D
		if mat == null:
			continue
		mat.metallic = 0.0
		mat.metallic_specular = 0.2
		mat.roughness = 0.78
		mat.emission_enabled = false
		mat.emission_energy_multiplier = 0.0
		mat.emission = Color(0, 0, 0, 1)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		# warm multiply toward concept_A (saturated red / peach / straw) without adding light
		mat.albedo_color = _boy_albedo_day
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		mat.disable_receive_shadows = false
		# Tripo/Mixamo can flip face/limb normals; back-face cull blacks out the face under
		# the brim while the vest still lights. Match the old boy.gdshader (cull_disabled).
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		_boy_mat = mat
		_boy_albedo_tex_day = mat.albedo_texture
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.transparency = 0
		# layer 1 (world) + layer 2 (face fill only) — still lit by the sun on layer 1
		mi.layers = 1 | 2
		break


## Closed-eye albedo / morph abandoned for Tripo shells — always keep day albedo.
func _set_eyes_closed(_closed: bool) -> void:
	if _boy_mat == null:
		return
	_eyes_closed_tex = false
	if _boy_albedo_tex_day == null:
		return
	_boy_mat.albedo_texture = _boy_albedo_tex_day
	if _body_mi:
		_body_mi.material_override = _boy_mat
		if _body_mi.mesh and _body_mi.mesh.get_surface_count() > 0:
			_body_mi.mesh.surface_set_material(0, _boy_mat)


func b2g(v) -> Vector3:
	# Blender Z-up meta coords -> Godot Y-up, then SCALE
	if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_PACKED_FLOAT32_ARRAY:
		return Vector3(-float(v[0]), float(v[2]) - float(meta["ground"]), float(v[1])) * SCALE
	return Vector3(-v.x, v.z - float(meta["ground"]), v.y) * SCALE


func _probe_release(_clip: String) -> Vector3:
	# palm roughly ahead of right hand in boy space
	var bi := skel.find_bone(B_HAND_R)
	if bi < 0:
		return Vector3(0.15, 0.55, -0.2)
	var p: Vector3 = skel.get_bone_global_pose(bi).origin
	return Vector3(p.x, p.y, p.z) + Vector3(0.05, 0.02, -0.08)


# ------------------------------------------------------------------ public API

func set_idle() -> void:
	# keep the march going through a turn on the spot (main calls set_idle while speed is ~0)
	if pivoting:
		return
	if anim == "charge" or anim == "move":
		_to_idle()


func set_move(speed: float) -> void:
	move_speed = speed
	if (speed > 0.05 or pivoting) and (anim == "idle" or anim == "react" or (pivoting and anim != "move")):
		if anim != "move" and move_w < 0.05:
			phase = 0.0
		anim = "move"
		stopping = false
		act_target = 0.0
		act_rate = 8.0


func charge(p: float) -> void:
	if anim != "charge":
		var fade := 0.0 if act_w < 0.05 else 0.3
		anim = "charge"
		anim_t = 0.0
		act_target = 1.0
		act_rate = 6.0
		_play(_throw_clip(), 0.0, fade, fade > 0.0)
	power = p


func start_throw(p: float) -> void:
	throw_power = p
	anim = "throw"
	anim_t = 0.0
	did_release = false
	act_target = 1.0
	var tc := float(clips[_throw_clip()].get("t_charge", 0.35))
	_play(_throw_clip(), tc, 0.08, true)


func react(kind: String) -> void:
	react_kind = kind
	if kind == "":
		set_face_expr("smile")
		_to_idle()
		return
	anim = "react"
	anim_t = 0.0
	act_target = 1.0
	act_rate = 5.0
	set_face_expr("cheer" if kind == "cheer" else "smile")
	var clip := "cheer" if kind == "cheer" else ("wave" if clips.has("wave") else "cheer")
	if kind == "oops" and clips.has("oops"):
		clip = "oops" if ap.has_animation("oops") else "wave"
	_play(clip, 0.0, 0.25)


func show_stone(v: bool) -> void:
	if stone:
		stone.visible = v


func foot_points(side: int) -> Array:
	var heel := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(B_FOOT[side])).origin
	var ball := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(B_TOE[side])).origin
	return [heel, ball]


func activity(kind: String, sit_k: float, lie_k: float, tt: float) -> Vector3:
	if anim != "activity":
		pre_act = [anim, act_w, act_target, slot_clip.duplicate(), slot_t.duplicate(), cur_slot, ab_w]
		act_frames = 0
		prev_sit = 0.0 if sit_k < 1.0 else 1.0
		prev_lie = 0.0
	anim = "activity"
	act_kind = kind
	act_lie_k = lie_k
	act_tt = tt
	var pre: String = {"sleep": "hammock_", "sun": "sun_", "seat": "seat_", "seatlie": "seat_"}[kind]
	var clip: String
	var u: float
	if kind == "seatlie" and lie_k >= 1.0:
		clip = "seat_nap"; u = fposmod(tt, 4.0) / 4.0
	elif kind == "seat" and lie_k >= 1.0:
		clip = "seat_rest"; u = fposmod(tt, 4.0) / 4.0
	elif lie_k <= 0.0:
		var down := sit_k >= prev_sit
		clip = pre + ("sit" if down else "stand")
		u = smoothstep(0.0, 1.0, sit_k) if down else 1.0 - smoothstep(0.0, 1.0, sit_k)
	elif lie_k < 1.0:
		var down2 := lie_k >= prev_lie
		clip = pre + ("lie" if down2 else "up")
		u = smoothstep(0.0, 1.0, lie_k) if down2 else 1.0 - smoothstep(0.0, 1.0, lie_k)
	else:
		clip = pre + ("sleep" if kind == "sleep" else "rest")
		u = fposmod(tt, 4.0) / 4.0
	prev_sit = sit_k
	prev_lie = lie_k
	# Sitting uses Tripo sit; full lie freezes the AnimationTree and poses bones to a flat supine
	var play_clip := "sit"
	var seek_len := float(clips["sit"]["length"])
	var full_lie := lie_k > 0.45 and kind in ["sun", "sleep", "seatlie"]
	if sit_k < 0.05 and lie_k <= 0.0:
		play_clip = "idle"
		seek_len = float(clips["idle"]["length"])
	elif full_lie:
		play_clip = "idle"
		seek_len = float(clips["idle"]["length"])
		u = 0.0
	# Instant action-slot blend when already seated — otherwise ab_w stays on the idle slot
	# (shots/selftest with process paused looked like a standing T-pose).
	var fade := 0.0 if (full_lie or sit_k >= 0.95) else 0.2
	_play(play_clip, clampf(u, 0.0, 0.99) * seek_len, fade)
	act_target = 1.0
	act_w = 1.0 if sit_k > 0.02 or lie_k > 0.0 else act_w
	act_rate = 8.0
	if sit_k >= 0.95 or full_lie:
		ab_w = float(cur_slot)
	hat_s = 1.0 if lie_k > 0.7 else 0.0
	glasses.visible = kind == "sun" and lie_k > 0.5
	blob.visible = sit_k < 0.3 and lie_k <= 0.0
	show_stone(false)
	model.rotation.x = 0.0
	# lie_settle used to nudge model.position.y, but once rest_lie_b is applied that local +Y
	# is the head axis (along the bed), not world-up — so it slid him along the towel/hammock.
	# Height above the surface is owned by main's rest_lie.y only.
	lie_settle = 0.0
	model.position = model_base
	if full_lie:
		_seed_lie_from_sit()
		_apply_lie_pose(kind, lie_k, tt)
		# Seek clears pose overrides — keep thighs planted on the lounger cushion.
		if lie_foot_plant and kind == "sun":
			plant_feet_on_plane(lie_foot_plane_point, lie_foot_plane_normal, lie_foot_plant_gap, true)
		# Hat stays on the head; contact via head tilt in the lie poses.
		sync_hat_lie(kind, lie_k)
	else:
		sync_hat_lie(kind, 0.0)
		# Single sit path: idle seed + additive L-sit (no Mixamo sit clip stack — that
		# rubber-hosed thighs mid-transition in v24).
		var sit_w := smoothstep(0.05, 1.0, sit_k) * (1.0 - lie_k)
		if kind in ["seat", "sleep", "sun"] and sit_w > 0.02:
			_seed_lie_from_sit()
			_apply_ergonomic_sit(sit_w)
		else:
			if ap and not ap.active:
				ap.active = true
			if tree and not tree.active:
				tree.active = true
			_apply_mixer()
	var pel := _live_pelvis()
	if pel.y < 0.05:
		pel = Vector3(0.0, Island.SEAT_TOP, 0.0)
	return pel


func end_activity() -> void:
	hat_s = 0.0
	hat_hold = 0.0
	set_hat_mode("head")
	glasses.visible = false
	blob.visible = true
	model.rotation.x = 0.0
	lie_settle = 0.0
	act_kind = ""
	act_lie_k = 0.0
	lie_foot_plant = false
	model.position = model_base
	clear_foot_plant()
	if ap:
		ap.active = true
	if tree:
		tree.active = true
	if act_frames == 0 and pre_act.size() == 7:
		anim = pre_act[0]; act_w = pre_act[1]; act_target = pre_act[2]
		slot_clip.assign(pre_act[3]); slot_t.assign(pre_act[4]); cur_slot = pre_act[5]; ab_w = pre_act[6]
		_set_slot(0, slot_clip[0], slot_t[0])
		_set_slot(1, slot_clip[1], slot_t[1])
		return
	_to_idle()
	act_w = 0.0
	has_prev = false
	show_stone(true)


## Seed bone poses from the idle clip (straight legs, natural cloth) instead of the bind/T-pose,
## which stretches the Tripo shorts into a yellow spike once the root is horizontal.
## Keep any foot-plant overrides — main re-applies them after the world transform each frame.
func _seed_lie_from_sit() -> void:
	if tree:
		tree.active = false
	if ap == null:
		_reset_to_rest_pose()
		return
	ap.active = true
	var clip := "idle" if ap.has_animation("idle") else ("sit" if ap.has_animation("sit") else "")
	if clip != "":
		ap.play(clip)
		var clen := float(clips.get(clip, {}).get("length", 1.0))
		ap.seek(minf(0.2, clen * 0.25), true)
		ap.advance(0.0)
	ap.active = false
	if skel:
		skel.force_update_transform()


## Dedicated per-spot supine poses layered on the idle seed. rest_lie_b sends boy −Z (chest)
## away from the support; keep arm eulers alone (overwriting them stretches the shorts spike).
func _apply_lie_pose(kind: String, lie_k: float, tt: float) -> void:
	var w := smoothstep(0.0, 1.0, lie_k)
	if w <= 0.001 or skel == null:
		return
	var breath := sin(tt * 1.35) * 0.02 * w
	if kind == "sleep":
		_apply_hammock_pose(w, breath)
	elif kind == "sun":
		_apply_lounger_pose(w, breath)
	else:
		_apply_seatlie_pose(w, breath)
	skel.force_update_transform()


## Lounger: hips in the crease, back flat on the ~40° pad. Head turns away from the
## approach side; forearm rests over the eyes (classic nap — eyes stay open).
func _apply_lounger_pose(w: float, breath: float) -> void:
	# Root basis follows the ~40° backrest. Do NOT pitch Hips — that tilts the whole
	# torso off the pad (#45 upright hunch). Bend UpLegs instead so thighs lie on the seat.
	_pose_abs("mixamorig_Hips", Vector3(0.0, 0.0, 0.0), w * 0.5)
	_pose_abs("mixamorig_Spine", Vector3(-0.02 + breath * 0.04, 0.0, 0.0), w)
	_pose_abs("mixamorig_Spine1", Vector3(-0.02 + breath * 0.05, 0.0, 0.0), w)
	_pose_abs("mixamorig_Spine2", Vector3(-0.01 + breath * 0.03, 0.0, 0.0), w)
	# Yaw away from the approach side + chin tip; keep mild so the brim doesn't dig the pad.
	_pose_abs("mixamorig_Neck", Vector3(-0.10, 0.22, 0.05), w)
	_pose_abs("mixamorig_Head", Vector3(-0.14 + breath * 0.02, 0.38, 0.06), w)
	# ~40° crease: thighs along the seat toward the foot end (keeps Mixamo UpLeg π twist).
	_pose_add("mixamorig_LeftUpLeg", Vector3(-0.75, 0.06, 0.10), w)
	_pose_add("mixamorig_RightUpLeg", Vector3(-0.75, -0.06, -0.10), w)
	_pose_add("mixamorig_LeftLeg", Vector3(0.22, 0.0, 0.0), w * 0.7)
	_pose_add("mixamorig_RightLeg", Vector3(0.22, 0.0, 0.0), w * 0.7)
	_pose_add("mixamorig_LeftFoot", Vector3(0.05, 0.0, 0.16), w * 0.55)
	_pose_add("mixamorig_RightFoot", Vector3(0.05, 0.0, -0.16), w * 0.55)
	_nap_forearm_over_eyes(w, "sun")

## Hammock: curl into the occupied cradle. Head turns away; forearm covers the eyes.
## Hat stays on — slight forward tip so the brim rests on the fabric.
## Mid climb-in: reach for the near lip, one knee up, weight leaning into the fabric.
func apply_hammock_climb(w: float) -> void:
	if skel == null or w <= 0.001:
		return
	_seed_lie_from_sit()
	var k := smoothstep(0.0, 1.0, w)
	# Readable climb: torso lean into fabric, one knee hiked onto the lip, both hands on rails.
	_pose_add("mixamorig_Spine", Vector3(0.45, 0.0, 0.0), k)
	_pose_add("mixamorig_Spine1", Vector3(0.25, 0.0, 0.0), k * 0.8)
	_pose_add("mixamorig_LeftUpLeg", Vector3(-1.45, 0.45, 0.25), k)
	_pose_add("mixamorig_RightUpLeg", Vector3(-0.35, -0.10, -0.08), k * 0.6)
	_pose_add("mixamorig_LeftLeg", Vector3(-0.35, 0.0, 0.0), k)
	_pose_add("mixamorig_RightLeg", Vector3(0.15, 0.0, 0.0), k * 0.5)
	_pose_add("mixamorig_LeftArm", Vector3(-1.10, 0.70, -0.45), k)
	_pose_add("mixamorig_RightArm", Vector3(-0.85, -0.55, 0.35), k)
	_pose_add("mixamorig_LeftForeArm", Vector3(-1.10, 0.15, 0.0), k)
	_pose_add("mixamorig_RightForeArm", Vector3(-0.95, -0.12, 0.0), k)
	skel.force_update_transform()


func _apply_hammock_pose(w: float, breath: float) -> void:
	_pose_abs("mixamorig_Spine", Vector3(0.10 + breath * 0.08, 0.0, 0.0), w)
	_pose_abs("mixamorig_Spine1", Vector3(0.12 + breath * 0.1, 0.0, 0.0), w)
	_pose_abs("mixamorig_Spine2", Vector3(0.08 + breath * 0.06, 0.0, 0.0), w)
	# Mild chin tuck only — large head yaw/roll laid the brim sideways across the fabric.
	_pose_abs("mixamorig_Neck", Vector3(-0.12, 0.06, 0.02), w)
	_pose_abs("mixamorig_Head", Vector3(-0.18 + breath * 0.02, 0.08, 0.02), w)
	# Soft knee curl so shins follow the cradle instead of a stiff plank.
	_pose_add("mixamorig_LeftUpLeg", Vector3(-0.55, 0.12, 0.18), w * 0.85)
	_pose_add("mixamorig_RightUpLeg", Vector3(-0.55, -0.12, -0.18), w * 0.85)
	_pose_add("mixamorig_LeftLeg", Vector3(0.95, 0.0, 0.0), w * 0.8)
	_pose_add("mixamorig_RightLeg", Vector3(0.95, 0.0, 0.0), w * 0.8)
	_pose_add("mixamorig_LeftFoot", Vector3(0.15, 0.0, 0.12), w * 0.55)
	_pose_add("mixamorig_RightFoot", Vector3(0.15, 0.0, -0.12), w * 0.55)
	_nap_forearm_over_eyes(w, "sleep")
	set_face_expr("sleep")


## Classic nap: left hand on belly, right forearm draped across the eyes (in front of
## the face, never through the skull or hat crown). Eyes stay open underneath.
## Only plant the RightHand — ForeArm/Arm overrides stretch Tripo skin through the head.
func _nap_forearm_over_eyes(w: float, kind: String = "sleep") -> void:
	if skel == null or w < 0.05:
		return
	skel.force_update_transform()
	var face: Vector3 = model.global_transform.basis.z.normalized() if model else (-global_transform.basis.z).normalized()
	var hips_p: Vector3 = lie_bone_world(B_HIPS)
	var head_p: Vector3 = lie_bone_world(B_HEAD)
	var head_dir: Vector3 = (head_p - hips_p).normalized()
	var side: Vector3 = face.cross(head_dir).normalized()
	if side.length_squared() < 1e-6:
		side = global_transform.basis.x.normalized()
	# Hammock (flat supine): absolute fold from arm scan. Lounger (~40° recline): soft
	# additive only — absolute Mixamo eulers rubber-hose the arm through the neck there.
	if kind == "sun":
		_pose_add("mixamorig_RightArm", Vector3(-0.45, -0.70, 0.35), w * 0.7)
		_pose_add("mixamorig_RightForeArm", Vector3(-0.85, 0.10, 0.15), w * 0.75)
		_pose_add("mixamorig_LeftArm", Vector3(0.20, 0.30, -0.35), w * 0.5)
		_pose_add("mixamorig_LeftForeArm", Vector3(-0.45, 0.15, 0.0), w * 0.5)
	else:
		_pose_abs("mixamorig_RightArm", Vector3(-0.95, -1.45, 0.55), w)
		_pose_abs("mixamorig_RightForeArm", Vector3(-1.55, 0.05, 0.25), w)
		_pose_abs("mixamorig_RightHand", Vector3(0.10, 0.15, 0.40), w * 0.6)
		_pose_abs("mixamorig_LeftArm", Vector3(0.30, 0.45, -0.50), w * 0.65)
		_pose_abs("mixamorig_LeftForeArm", Vector3(-0.60, 0.20, 0.0), w * 0.65)
	skel.force_update_transform()
	head_p = lie_bone_world(B_HEAD)
	# Wrist over the eyes. Lounger: a bit further out so we don't tunnel the cheek.
	var out := 0.13 if kind == "sun" else 0.11
	var wrist: Vector3 = head_p + face * out - head_dir * 0.005 - side * 0.05
	var belly: Vector3 = lie_bone_world("mixamorig_Spine2") + face * 0.12 - head_dir * 0.02 + side * 0.07
	var top_bi := skel.find_bone("mixamorig_HeadTop_End")
	if top_bi >= 0:
		var top_p: Vector3 = (skel.global_transform * skel.get_bone_global_pose(top_bi)).origin
		var crown_n := (top_p - head_p).normalized()
		var up_amt := (wrist - head_p).dot(crown_n)
		var max_up := (top_p - head_p).dot(crown_n) * 0.20
		if up_amt > max_up:
			wrist -= crown_n * (up_amt - max_up)
	var into := (wrist - head_p).dot(face)
	var min_into := 0.10 if kind == "sun" else 0.09
	if into < min_into:
		wrist += face * (min_into - into)
	# Plant hand only (ForeArm override rubber-hoses Tripo skin through the skull).
	for bone_name in ["mixamorig_RightHand", "mixamorig_LeftHand"]:
		var bi := skel.find_bone(bone_name)
		if bi < 0:
			continue
		var goal: Vector3 = wrist if bone_name == "mixamorig_RightHand" else belly
		var xf: Transform3D = skel.global_transform * skel.get_bone_global_pose(bi)
		goal = xf.origin.lerp(goal, clampf(w, 0.0, 1.0))
		var planted := Transform3D(xf.basis, goal)
		var local_xf: Transform3D = skel.global_transform.affine_inverse() * planted
		skel.set_bone_global_pose_override(bi, local_xf, w, true)
	skel.force_update_transform()


## Place both hands on the belly (chest-sky side) so they never tunnel through the support.
func _rest_hands_on_belly(w: float) -> void:
	if skel == null or w < 0.05:
		return
	skel.force_update_transform()
	# Boy chest/face = −into when supine (model +Z with y=PI).
	var face: Vector3 = -global_transform.basis.z.normalized()
	if model != null and is_instance_valid(model):
		face = model.global_transform.basis.z.normalized()
	var along: Vector3 = global_transform.basis.y.normalized()
	var side: Vector3 = face.cross(along).normalized()
	if side.length_squared() < 1e-6:
		side = global_transform.basis.x.normalized()
	var belly: Vector3 = lie_bone_world("mixamorig_Spine2") + face * 0.11 - along * 0.04
	var targets := {
		"mixamorig_LeftHand": belly + side * 0.09,
		"mixamorig_RightHand": belly - side * 0.09,
	}
	for bone_name in targets.keys():
		var bi := skel.find_bone(bone_name)
		if bi < 0:
			continue
		var xf: Transform3D = skel.global_transform * skel.get_bone_global_pose(bi)
		var goal: Vector3 = xf.origin.lerp(targets[bone_name] as Vector3, clampf(w, 0.0, 1.0))
		var planted := Transform3D(xf.basis, goal)
		var local_xf: Transform3D = skel.global_transform.affine_inverse() * planted
		skel.set_bone_global_pose_override(bi, local_xf, w, true)
	skel.force_update_transform()



## Plant feet / knees / mid-thighs onto a world-space seat plane so legs don't punch through.
func plant_feet_on_plane(plane_point: Vector3, plane_normal: Vector3, gap := 0.012, include_knees := true) -> void:
	if skel == null:
		return
	plane_normal = plane_normal.normalized()
	# Feet + knees only. UpLeg overrides stretch Tripo thigh skin through the cushion.
	var bones: Array[String] = [B_FOOT[0], B_FOOT[1]]
	if include_knees:
		bones.append_array(["mixamorig_LeftLeg", "mixamorig_RightLeg"])
	for bone_name in bones:
		var bi := skel.find_bone(bone_name)
		if bi < 0:
			continue
		var xf: Transform3D = skel.global_transform * skel.get_bone_global_pose(bi)
		var g := (xf.origin - plane_point).dot(plane_normal)
		# Only lift out of the pad.
		if g >= gap:
			continue
		var planted := Transform3D(xf.basis, xf.origin - plane_normal * (g - gap))
		var local_xf: Transform3D = skel.global_transform.affine_inverse() * planted
		skel.set_bone_global_pose_override(bi, local_xf, 1.0, true)
	skel.force_update_transform()


## Snap both feet onto a ground plane (pull down or lift) so a park-bench sit plants soles.
## Caps the pull so short Tripo shins don't rubber-hose through the seat board.
func plant_feet_to_ground(plane_point: Vector3, plane_normal: Vector3 = Vector3.UP, gap := 0.02) -> void:
	if skel == null:
		return
	plane_normal = plane_normal.normalized()
	skel.force_update_transform()
	const MAX_PULL := 0.12
	for bone_name in [B_FOOT[0], B_FOOT[1]]:
		var bi := skel.find_bone(bone_name)
		if bi < 0:
			continue
		var xf: Transform3D = skel.global_transform * skel.get_bone_global_pose(bi)
		var g := (xf.origin - plane_point).dot(plane_normal)
		var pull := clampf(g - gap, -MAX_PULL, MAX_PULL)
		var planted := Transform3D(xf.basis, xf.origin - plane_normal * pull)
		var local_xf: Transform3D = skel.global_transform.affine_inverse() * planted
		skel.set_bone_global_pose_override(bi, local_xf, 1.0, true)
	skel.force_update_transform()


## Clear any foot pose overrides (call when leaving lie / before reseeding).
func clear_foot_plant() -> void:
	if skel == null:
		return
	skel.clear_bones_global_pose_override()
	skel.force_update_transform()


## Bench / log lie-back: soft flat supine with bent knees + hands on belly.
func _apply_seatlie_pose(w: float, breath: float) -> void:
	_pose_abs("mixamorig_Spine", Vector3(0.04 + breath * 0.4, 0.0, 0.0), w)
	_pose_abs("mixamorig_Spine1", Vector3(0.05 + breath * 0.5, 0.0, 0.0), w)
	_pose_abs("mixamorig_Spine2", Vector3(0.04 + breath * 0.3, 0.0, 0.0), w)
	_pose_abs("mixamorig_Neck", Vector3(-0.1, 0.08, 0.0), w)
	_pose_abs("mixamorig_Head", Vector3(-0.15 + breath * 0.2, 0.1, 0.0), w)
	_pose_add("mixamorig_LeftUpLeg", Vector3(-0.45, 0.1, 0.12), w * 0.75)
	_pose_add("mixamorig_RightUpLeg", Vector3(-0.45, -0.1, -0.12), w * 0.75)
	_pose_add("mixamorig_LeftLeg", Vector3(0.85, 0.0, 0.0), w * 0.7)
	_pose_add("mixamorig_RightLeg", Vector3(0.85, 0.0, 0.0), w * 0.7)
	_pose_add("mixamorig_LeftArm", Vector3(0.25, 0.35, -0.4), w * 0.55)
	_pose_add("mixamorig_RightArm", Vector3(0.25, -0.35, 0.4), w * 0.55)
	_pose_add("mixamorig_LeftForeArm", Vector3(-0.55, 0.1, 0.0), w * 0.55)
	_pose_add("mixamorig_RightForeArm", Vector3(-0.55, -0.1, 0.0), w * 0.55)


func _pose_abs(bone: String, euler: Vector3, w: float) -> void:
	var bi := skel.find_bone(bone)
	if bi < 0:
		return
	skel.set_bone_pose_rotation(bi, Quaternion.IDENTITY.slerp(Quaternion.from_euler(euler), w))


## Layer a small euler on top of the current (idle-seed) pose — keeps natural leg bend.
func _pose_add(bone: String, euler: Vector3, w: float) -> void:
	var bi := skel.find_bone(bone)
	if bi < 0:
		return
	var cur: Quaternion = skel.get_bone_pose_rotation(bi)
	var add := Quaternion.from_euler(euler)
	skel.set_bone_pose_rotation(bi, cur.slerp(add * cur, w))


## Upright chair/log/hammock sit: additive on idle seed (keeps Mixamo UpLeg rest twist).
## Mild yaw so both feet stay forward of the hips along seat face.
func _apply_ergonomic_sit(w: float) -> void:
	if skel == null or w <= 0.001:
		return
	var k := smoothstep(0.0, 1.0, w)
	# Park-bench L-sit: thighs on the board, shins down toward the ground in front
	# (less knee tuck than the deep under-seat curl — that perched a foot on the seat).
	_pose_add("mixamorig_LeftUpLeg", Vector3(-1.15, 0.18, 0.12), k)
	_pose_add("mixamorig_RightUpLeg", Vector3(-1.15, -0.18, -0.12), k)
	_pose_add("mixamorig_LeftLeg", Vector3(0.95, 0.0, 0.0), k)
	_pose_add("mixamorig_RightLeg", Vector3(0.95, 0.0, 0.0), k)
	_pose_add("mixamorig_LeftFoot", Vector3(0.12, 0.0, 0.04), k * 0.7)
	_pose_add("mixamorig_RightFoot", Vector3(0.12, 0.0, -0.04), k * 0.7)
	_pose_add("mixamorig_Spine", Vector3(-0.08, 0.0, 0.0), k * 0.55)
	_pose_add("mixamorig_Spine1", Vector3(-0.05, 0.0, 0.0), k * 0.45)
	_pose_add("mixamorig_LeftArm", Vector3(0.30, 0.22, -0.22), k * 0.65)
	_pose_add("mixamorig_RightArm", Vector3(0.30, -0.22, 0.22), k * 0.65)
	_pose_add("mixamorig_LeftForeArm", Vector3(-0.50, 0.12, 0.0), k * 0.7)
	_pose_add("mixamorig_RightForeArm", Vector3(-0.50, -0.12, 0.0), k * 0.7)
	skel.force_update_transform()


## Bake the current skeleton pose into a static ArrayMesh so stills show deformation on
## drivers that leave the skinned mesh at bind pose (llvmpipe Compatibility).
func bake_pose_mesh() -> void:
	_ensure_skin_cache()
	if skel == null or _body_mi == null or _skin_verts.is_empty():
		return
	skel.force_update_transform()
	var n: int = _skin_verts.size()
	var bone_xf: Array[Transform3D] = []
	bone_xf.resize(skel.get_bone_count())
	for bi in skel.get_bone_count():
		# Skinning in skeleton space (mesh is child of Skeleton3D).
		bone_xf[bi] = skel.get_bone_global_pose(bi) * skel.get_bone_global_rest(bi).affine_inverse()
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		var v: Vector3 = _skin_verts[i]
		var skinned := Vector3.ZERO
		var wsum := 0.0
		for j in 4:
			var bi2: int = _skin_bones[i * 4 + j]
			var w: float = _skin_weights[i * 4 + j]
			if w <= 0.0 or bi2 < 0 or bi2 >= bone_xf.size():
				continue
			skinned += bone_xf[bi2] * v * w
			wsum += w
		out[i] = skinned / wsum if wsum > 0.01 else v
	var arrays: Array = _body_arrays_orig.duplicate(true)
	arrays[Mesh.ARRAY_VERTEX] = out
	# Drop bone weights so the mesh is treated as static (already posed).
	arrays[Mesh.ARRAY_BONES] = null
	arrays[Mesh.ARRAY_WEIGHTS] = null
	var baked := ArrayMesh.new()
	var fmt: int = 0
	if _body_mesh_orig is ArrayMesh:
		fmt = int((_body_mesh_orig as ArrayMesh).surface_get_format(0))
	fmt &= ~(Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS)
	# Rebuild arrays without bone streams (static posed mesh).
	var clean: Array = []
	clean.resize(Mesh.ARRAY_MAX)
	for ai in Mesh.ARRAY_MAX:
		if ai == Mesh.ARRAY_BONES or ai == Mesh.ARRAY_WEIGHTS:
			continue
		clean[ai] = arrays[ai]
	baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, clean, [], {}, fmt)
	if _body_mesh_orig is ArrayMesh and (_body_mesh_orig as ArrayMesh).surface_get_material(0):
		baked.surface_set_material(0, (_body_mesh_orig as ArrayMesh).surface_get_material(0))
	_body_mi.mesh = baked
	_body_mi.skeleton = NodePath()
	_body_mi.skin = null
	_pose_baked = true


func restore_pose_mesh() -> void:
	if not _pose_baked or _body_mi == null:
		return
	_body_mi.mesh = _body_mesh_orig
	_body_mi.skeleton = _body_skel_path
	_body_mi.skin = _body_skin_orig
	_pose_baked = false


## World elevation of hip→knee (0° = horizontal thigh). Positive = knee above hip.
func sit_thigh_elev_deg() -> float:
	var hips := lie_bone_world("mixamorig_Hips")
	var knee := lie_bone_world("mixamorig_LeftLeg")
	var d := knee - hips
	if d.length_squared() < 1e-8:
		return 90.0
	return rad_to_deg(asin(clampf(d.normalized().dot(Vector3.UP), -1.0, 1.0)))


## World positions of key bones after the current lie pose (for contact checks / snaps).
func lie_bone_world(bone: String) -> Vector3:
	if skel == null:
		return global_position
	var bi := skel.find_bone(bone)
	if bi < 0:
		return global_position
	return (skel.global_transform * skel.get_bone_global_pose(bi)).origin


## Unit chest/face normal (skyward when supine). Tripo chest faces model +Z; with model.rotation.y
## = PI that is boy −Z. Selftest requires this · UP > 0.5 in both lie states.
func lie_face_normal() -> Vector3:
	if model != null and is_instance_valid(model):
		var n: Vector3 = model.global_transform.basis.z
		if n.length_squared() > 1e-8:
			return n.normalized()
	return (-global_transform.basis.z).normalized()


## Approximate back-of-body contact points (hips / mid-spine / head / both feet) in world space.
## into_bed pushes from the bone toward the support (mesh shell — Tripo shorts/hat need margin).
func lie_contact_points(into_bed: Vector3, back_offset := 0.04) -> Dictionary:
	into_bed = into_bed.normalized()
	var hips := lie_bone_world(B_HIPS) + into_bed * back_offset
	var spine := lie_bone_world("mixamorig_Spine1") + into_bed * back_offset
	var head := lie_bone_world(B_HEAD) + into_bed * (back_offset + 0.02)
	var foot_l := lie_bone_world(B_FOOT[0]) + into_bed * 0.02
	var foot_r := lie_bone_world(B_FOOT[1]) + into_bed * 0.02
	return {"hips": hips, "spine": spine, "head": head, "foot_l": foot_l, "foot_r": foot_r}


## Cached bind-pose skin buffers for lie penetration (BoyMesh + baked hat verts).
var _skin_verts: PackedVector3Array = PackedVector3Array()
var _skin_bones: PackedInt32Array = PackedInt32Array()
var _skin_weights: PackedFloat32Array = PackedFloat32Array()
var _skin_ready := false
var _body_mi: MeshInstance3D
var _body_mesh_orig: Mesh
var _body_skin_orig: Skin
var _body_skel_path: NodePath = NodePath("..")
var _body_arrays_orig: Array = []
## llvmpipe / some GL paths leave the GPU mesh at bind pose; bake CPU-skinned verts for stills.
var _pose_baked := false


func _ensure_skin_cache() -> void:
	if _skin_ready or skel == null:
		return
	_skin_ready = true
	for c in skel.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() < 1:
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones_a = arrays[Mesh.ARRAY_BONES]
		var weights_a = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones_a == null or weights_a == null:
			continue
		_body_mi = mi
		_body_mesh_orig = mi.mesh
		_body_skin_orig = mi.skin
		_body_skel_path = mi.skeleton
		_body_arrays_orig = arrays.duplicate(true)
		_skin_verts = verts
		# Godot may store bones as PackedInt32Array or PackedFloat32Array depending on importer.
		_skin_bones = PackedInt32Array()
		_skin_bones.resize(verts.size() * 4)
		_skin_weights = PackedFloat32Array()
		_skin_weights.resize(verts.size() * 4)
		for i in verts.size() * 4:
			_skin_bones[i] = int(bones_a[i])
			_skin_weights[i] = float(weights_a[i])
		# Index crown/brim verts (head-weighted, high in head-local Y) for hat penet.
		_hat_skin_idxs = PackedInt32Array()
		var head_i := skel.find_bone(B_HEAD)
		if head_i >= 0:
			var head_inv: Transform3D = skel.get_bone_global_rest(head_i).affine_inverse()
			for vi in verts.size():
				var wh := 0.0
				for j in 4:
					if int(bones_a[vi * 4 + j]) == head_i:
						wh += float(weights_a[vi * 4 + j])
				if wh < 0.28:
					continue
				var local: Vector3 = head_inv * verts[vi]
				var r := Vector2(local.x, local.z).length()
				# Crown + brim shell — skip face shell under the brim.
				var face_shell := local.y < 0.14 and r < 0.11 and local.z > -0.01
				if face_shell:
					continue
				if local.y > 0.08 and (r > 0.08 or local.y > 0.18):
					_hat_skin_idxs.append(vi)
		break


## Sample skinned mesh vertices in world space (stride so ~max_samples points).
## Includes the baked hat; hat_sample_world densifies crown/brim for contact tests.
func skinned_sample_world(max_samples := 500) -> Array[Vector3]:
	_ensure_skin_cache()
	var out: Array[Vector3] = []
	if skel == null or _skin_verts.is_empty():
		return out
	skel.force_update_transform()
	var n: int = _skin_verts.size()
	var step: int = maxi(1, n / maxi(max_samples, 1))
	# Precompute bone world = skel.global * pose * rest_inv for used bones.
	var bone_xf: Array[Transform3D] = []
	bone_xf.resize(skel.get_bone_count())
	for bi in skel.get_bone_count():
		bone_xf[bi] = skel.global_transform * skel.get_bone_global_pose(bi) * skel.get_bone_global_rest(bi).affine_inverse()
	for i in range(0, n, step):
		var v: Vector3 = _skin_verts[i]
		var skinned := Vector3.ZERO
		var wsum := 0.0
		for j in 4:
			var bi: int = _skin_bones[i * 4 + j]
			var w: float = _skin_weights[i * 4 + j]
			if w <= 0.0 or bi < 0 or bi >= bone_xf.size():
				continue
			skinned += bone_xf[bi] * v * w
			wsum += w
		if wsum < 0.01:
			continue
		out.append(skinned / wsum)
	return out


## Sample baked straw-hat crown/brim verts in world space (for penetration / containment).
func hat_sample_world(max_samples := 160) -> Array[Vector3]:
	_ensure_skin_cache()
	var out: Array[Vector3] = []
	if skel == null or _hat_skin_idxs.is_empty():
		return out
	skel.force_update_transform()
	var bone_xf: Array[Transform3D] = []
	bone_xf.resize(skel.get_bone_count())
	for bi in skel.get_bone_count():
		bone_xf[bi] = skel.global_transform * skel.get_bone_global_pose(bi) * skel.get_bone_global_rest(bi).affine_inverse()
	var n: int = _hat_skin_idxs.size()
	var step: int = maxi(1, n / maxi(max_samples, 1))
	for k in range(0, n, step):
		var i: int = _hat_skin_idxs[k]
		var v: Vector3 = _skin_verts[i]
		var skinned := Vector3.ZERO
		var wsum := 0.0
		for j in 4:
			var bi: int = _skin_bones[i * 4 + j]
			var w: float = _skin_weights[i * 4 + j]
			if w <= 0.0 or bi < 0 or bi >= bone_xf.size():
				continue
			skinned += bone_xf[bi] * v * w
			wsum += w
		if wsum < 0.01:
			continue
		out.append(skinned / wsum)
	return out


func throw_stance() -> Array:
	return []


func _throw_clip() -> String:
	return "throw_stand"


func _to_idle() -> void:
	anim = "idle"
	act_target = 0.0
	act_rate = 6.0
	stopping = false
	react_kind = ""
	act_kind = ""
	act_lie_k = 0.0
	model.rotation.x = 0.0
	lie_settle = 0.0
	model.position = model_base
	if ap:
		ap.active = true
	if tree:
		tree.active = true


func _resolve_clip(name: String) -> String:
	if ap.has_animation(name):
		return name
	# aliases
	var map := {
		"stroll": "walk", "throw_crouch": "throw_stand", "oops": "wave",
		"sun_sit": "sit", "sun_lie": "sit", "sun_rest": "sit", "sun_up": "sit", "sun_stand": "idle",
		"hammock_sit": "sit", "hammock_lie": "sit", "hammock_sleep": "sit", "hammock_up": "sit", "hammock_stand": "idle",
		"seat_sit": "sit", "seat_rest": "sit", "seat_lie": "sit", "seat_nap": "sit", "seat_up": "sit", "seat_stand": "idle",
	}
	var a: String = map.get(name, "idle")
	return a if ap.has_animation(a) else "idle"


func _set_slot(i: int, clip: String, tseek: float) -> void:
	var real := _resolve_clip(clip)
	slot_clip[i] = clip
	slot_t[i] = tseek
	var node: AnimationNodeAnimation = bt.get_node("a" if i == 0 else "b")
	node.animation = real


func _play(clip: String, tseek: float, fade: float, force_slot := false) -> void:
	var same := slot_clip[cur_slot] == clip and not force_slot
	if same:
		slot_t[cur_slot] = tseek
		return
	var other := 1 - cur_slot
	_set_slot(other, clip, tseek)
	cur_slot = other
	if fade <= 0.0:
		ab_w = float(cur_slot)
	else:
		ab_rate = 1.0 / maxf(fade, 0.01)


func _live_pelvis() -> Vector3:
	if parts.has("pelvis") and is_instance_valid(parts["pelvis"]):
		return to_local((parts["pelvis"] as Node3D).global_position)
	var bi := skel.find_bone(B_HIPS)
	if bi < 0:
		return Vector3(0.0, Island.SEAT_TOP, 0.0)
	# bone pose is in skeleton/model space; account for model yaw flip + scale
	var p: Vector3 = skel.get_bone_global_pose(bi).origin
	return model.transform * p


func _track(clip: String, key: String, u: float) -> Vector3:
	var c: Dictionary = clips.get(clip, {})
	if not c.has(key):
		return _live_pelvis()
	var arr: Array = c[key]
	if arr.is_empty():
		return Vector3(0.0, SIT_HIPS_Y * SCALE, 0.0)
	if arr.size() == 1:
		return b2g(arr[0])
	var f := clampf(u, 0.0, 1.0) * float(arr.size() - 1)
	var i := mini(int(f), arr.size() - 2)
	return b2g(arr[i]).lerp(b2g(arr[i + 1]), f - float(i))


func _process(delta: float) -> void:
	if frozen:
		return
	_tick(delta)


func _tick(delta: float) -> void:
	lead_dt = delta
	act_frames += 1
	t += delta
	anim_t += delta
	act_w = move_toward(act_w, act_target, delta * act_rate)
	ab_w = move_toward(ab_w, float(cur_slot), delta * ab_rate)

	# spot-turn footfalls: 2–3 alternating steps (open / turn / close), no steps_taken
	if pivoting and not was_pivoting:
		spot_clock = 0.0
		spot_emitted = 0
		if anim != "move":
			anim = "move"
			act_target = 0.0
			move_w = maxf(move_w, 0.6)
	if pivoting:
		pivot_grace = 0.35
		spot_clock += delta
		# timed so a ~180° flick lands 2–3 spot steps before the heading settles
		var marks := [0.10, 0.38, 0.66]
		while spot_emitted < marks.size() and spot_clock >= float(marks[spot_emitted]):
			spot_steps += 1
			footstep.emit(spot_emitted % 2, false)
			foot_flat.emit(spot_emitted % 2)
			spot_emitted += 1
	else:
		pivot_grace = maxf(0.0, pivot_grace - delta)
	was_pivoting = pivoting

	# locomotion blends
	if anim == "move":
		speed_s = move_speed
		run_k = 0.0 if pivoting else smoothstep(RUN_FROM, RUN_TO, speed_s)
		# Light stick → stroll (soft), then walk. Keep walk_k for mix amount.
		walk_k = clampf(smoothstep(0.35, 1.05, speed_s), 0.0, 1.0)
		move_w = move_toward(move_w, 1.0, delta * 4.0)
		var dist := 0.0
		if has_prev:
			dist = Vector3(global_position.x - prev_pos.x, 0, global_position.z - prev_pos.z).length()
		prev_pos = global_position
		has_prev = true
		var stride := float(clips["run"]["stride"]) if run_k > 0.5 else float(clips["walk"]["stride"])
		# Match phase advance to travel so stance feet don't skate on the ground texture.
		var dphase := dist / maxf(stride, 0.05)
		if pivoting or dist < 0.001:
			dphase = delta / maxf(float(clips["walk"]["length"]), 0.2)
		phase = fposmod(phase + dphase, 1.0)
		# walking footfalls only when translating after the spot-turn grace window
		if not pivoting and pivot_grace <= 0.0:
			var side := 0 if phase < 0.5 else 1
			if side != _prev_phase_side and move_w > 0.5 and dist > 0.001:
				footstep.emit(side, run_k > 0.5)
				foot_flat.emit(side)
				steps_taken += 1
			_prev_phase_side = side
		elif pivoting or pivot_grace > 0.0:
			_prev_phase_side = -1
		t_idle = 0.0
	else:
		move_w = move_toward(move_w, 0.0, delta * 5.0)
		t_idle = fposmod(t_idle + delta, float(clips["idle"]["length"]))
		has_prev = false
		_prev_phase_side = -1

	# advance action slot times
	for i in 2:
		if slot_clip[i] != "":
			var real := _resolve_clip(slot_clip[i])
			var L := float(clips.get(slot_clip[i], clips.get(real, {"length": 1.0}))["length"])
			if anim in ["charge"]:
				# hold near start of throw (wind-up) based on power
				slot_t[i] = clampf(power, 0.0, 1.0) * float(clips[_throw_clip()].get("t_charge", 0.35))
			elif anim == "throw":
				var tc := float(clips[_throw_clip()].get("t_charge", 0.35))
				slot_t[i] = minf(tc + anim_t, L)
				var tr := float(clips[_throw_clip()].get("t_release", T_RELEASE))
				if not did_release and anim_t >= maxf(0.0, tr - tc):
					did_release = true
					show_stone(false)
					released.emit()
				if tc + anim_t >= L:
					_to_idle()
					show_stone(true)
			elif anim == "react":
				slot_t[i] = minf(anim_t, L)
				if anim_t >= L:
					_to_idle()
			elif anim == "activity":
				# keep seek set by _play
				pass
			else:
				slot_t[i] = fposmod(slot_t[i] + delta, maxf(L, 0.01)) if clips.get(slot_clip[i], {}).get("loop", false) else minf(slot_t[i] + delta, L)

	if anim == "activity" and act_lie_k > 0.45 and act_kind in ["sun", "sleep", "seatlie"]:
		_seed_lie_from_sit()
		_apply_lie_pose(act_kind, act_lie_k, act_tt)
		# Idle seek clears global pose overrides — re-plant so thighs stay ON the cushion.
		if lie_foot_plant and act_kind == "sun":
			plant_feet_on_plane(lie_foot_plane_point, lie_foot_plane_normal, lie_foot_plant_gap, true)
	elif anim == "activity" and act_lie_k < 0.45 and act_kind in ["seat", "sleep", "sun"] and act_w > 0.5:
		# Re-seed every tick — pose_add is relative; stacking without reset bends sideways.
		_seed_lie_from_sit()
		_apply_ergonomic_sit(clampf(act_w, 0.0, 1.0) * (1.0 - act_lie_k))
	else:
		if ap and not ap.active:
			ap.active = true
		if tree and not tree.active:
			tree.active = true
		_apply_mixer()
	_polish_gait(delta)
	_update_blob()
	_update_face(delta)


## Soft child gait on Mixamo: light limb boost, hip sway, bob, turn lean.
## Keep amps small — v24 overdrive made a conveyor/skating read next to AC.
func _polish_gait(delta: float) -> void:
	if skel == null or model == null:
		return
	if _settle_left > 0.0:
		_settle_left = maxf(0.0, _settle_left - delta)
	var moving := anim == "move" and move_w > 0.25 and not pivoting
	var bob_amp := 0.0
	var sway := 0.0
	if moving:
		var amp := lerpf(0.55, 0.85, run_k) * move_w
		bob_amp = lerpf(0.018, 0.032, run_k) * move_w
		# Soft forward lean + turn lean into corners.
		var upright := 0.04 + 0.06 * run_k + absf(turn_lean) * 0.08
		_pose_add("mixamorig_Spine", Vector3(-upright * 0.4, turn_lean * 0.12, turn_lean * 0.18), move_w * 0.55)
		_pose_add("mixamorig_Spine1", Vector3(-upright * 0.28, turn_lean * 0.08, 0.0), move_w * 0.5)
		var look_y := clampf(turn_ahead, -0.35, 0.35) * 0.4
		_pose_add("mixamorig_Head", Vector3(upright * 0.15, look_y, 0.0), move_w * 0.4)
		var s := sin(phase * TAU)
		var c := cos(phase * TAU)
		# Mild stride amplify (Mixamo already carries most of the motion).
		var hip_amp := lerpf(0.18, 0.28, run_k) * amp
		var knee_swing := lerpf(0.28, 0.42, run_k) * amp
		var knee_plant := lerpf(0.04, 0.08, run_k) * amp
		_pose_add("mixamorig_LeftUpLeg", Vector3(-hip_amp * s, 0.0, 0.06 * c), 0.7)
		_pose_add("mixamorig_RightUpLeg", Vector3(hip_amp * s, 0.0, -0.06 * c), 0.7)
		_pose_add("mixamorig_LeftLeg", Vector3(knee_swing * maxf(s, 0.0) + knee_plant * maxf(-s, 0.0), 0.0, 0.0), 0.7)
		_pose_add("mixamorig_RightLeg", Vector3(knee_swing * maxf(-s, 0.0) + knee_plant * maxf(s, 0.0), 0.0, 0.0), 0.7)
		_pose_add("mixamorig_LeftFoot", Vector3(0.18 * maxf(s, 0.0) - 0.1 * maxf(-s, 0.0), 0.0, 0.0), 0.55)
		_pose_add("mixamorig_RightFoot", Vector3(0.18 * maxf(-s, 0.0) - 0.1 * maxf(s, 0.0), 0.0, 0.0), 0.55)
		var swing := s * lerpf(0.45, 0.65, run_k) * amp
		_pose_add("mixamorig_LeftArm", Vector3(swing * 0.55, -swing * 0.08, -swing * 0.18), 0.75)
		_pose_add("mixamorig_RightArm", Vector3(-swing * 0.55, swing * 0.08, swing * 0.18), 0.75)
		_pose_add("mixamorig_LeftForeArm", Vector3(-absf(swing) * 0.35, 0.0, 0.0), 0.6)
		_pose_add("mixamorig_RightForeArm", Vector3(-absf(swing) * 0.35, 0.0, 0.0), 0.6)
		# Lateral weight shift toward the stance foot (AC-style hip sway).
		sway = -c * lerpf(0.012, 0.02, run_k) * move_w
		hip_shift = hip_shift.lerp(Vector3(sway, 0, 0), 1.0 - exp(-delta * 8.0))
		skel.force_update_transform()
	else:
		hip_shift = hip_shift.lerp(Vector3.ZERO, 1.0 - exp(-delta * 6.0))
	# Double-frequency bob: dip on each footfall, rise on mid-swing.
	var want_bob := -absf(sin(phase * TAU)) * bob_amp if moving else 0.0
	_walk_bob = lerpf(_walk_bob, want_bob, 1.0 - exp(-delta * 10.0))
	model.position = model_base + Vector3(hip_shift.x, _walk_bob, 0)


func _reset_to_rest_pose() -> void:
	if skel == null:
		return
	skel.reset_bone_poses()
	skel.force_update_transform()


func _apply_mixer() -> void:
	if tree == null:
		return
	var walk: Dictionary = clips["walk"]
	var run: Dictionary = clips["run"]
	tree.set("parameters/idle_s/seek_request", t_idle)
	tree.set("parameters/walk_s/seek_request", phase * float(walk["length"]))
	tree.set("parameters/run_s/seek_request", phase * float(run["length"]))
	tree.set("parameters/stroll_s/seek_request", phase * float(clips.get("stroll", walk)["length"]))
	tree.set("parameters/a_s/seek_request", slot_t[0])
	tree.set("parameters/b_s/seek_request", slot_t[1])
	tree.set("parameters/wr/blend_amount", run_k)
	tree.set("parameters/move/blend_amount", smoothstep(0.0, 1.0, move_w))
	tree.set("parameters/ab/blend_amount", ab_w)
	tree.set("parameters/act/blend_amount", act_w)
	tree.advance(0.0)
	if absf(aim_twist) > 1e-4:
		twist_spine(skel, aim_twist)


func _update_blob() -> void:
	if blob == null:
		return
	blob.position = Vector3(0, 0.01, 0)
	blob.visible = blob.visible and anim != "activity"


static func twist_spine(sk: Skeleton3D, tw: float) -> void:
	for j in TWIST_BONES.size():
		var bi := sk.find_bone(TWIST_BONES[j])
		if bi < 0:
			continue
		var par_i := sk.get_bone_parent(bi)
		if par_i < 0:
			continue
		var par := sk.get_bone_global_pose(par_i).basis
		var axis := (par.inverse() * Vector3.UP).normalized()
		sk.set_bone_pose_rotation(bi, Quaternion(axis, tw * float(TWIST_SHARE[j])) * sk.get_bone_pose_rotation(bi))


const SPOT_RATE := 3.4
const STEER_GRIP := 4.5
const STEER_TOP := 6.0

static func spot_turn(face: float, want: float, rate: float, delta: float) -> Array:
	var need := wrapf(want - face, -PI, PI)
	var top := minf(SPOT_RATE, 1.2 + absf(need) * 2.6)
	rate = move_toward(rate, top, delta * 14.0)
	var stp := minf(absf(need), rate * delta)
	return [face + signf(need) * stp, rate]


static func wants_spot_turn(need: float, speed: float) -> bool:
	return (absf(need) > 1.1 and speed < 0.4) or (absf(need) > 2.0 and speed < 0.9)


static func move_turn(face: float, want: float, speed: float, delta: float) -> Array:
	var need := wrapf(want - face, -PI, PI)
	var top := minf(STEER_TOP, STEER_GRIP / maxf(speed, 0.3))
	var stp := minf(absf(need), minf(top, absf(need) * 9.0) * delta)
	return [face + signf(need) * stp, 1.0 - 0.72 * smoothstep(0.5, 1.6, absf(need))]


func spin_busy() -> bool:
	# Only the post-pivot grace — do NOT include `pivoting` itself (that deadlocks
	# spot_turning forever: need≈0 but spin_busy stays true while pivoting is still set).
	return pivot_grace > 0.05 and not pivoting


func settling() -> bool:
	return _settle_left > 0.0


func begin_settle(seconds := 0.35) -> void:
	_settle_left = maxf(_settle_left, seconds)


func hat_seat(s := -1.0) -> Transform3D:
	return Transform3D.IDENTITY


func hat_on_head() -> Transform3D:
	return Transform3D.IDENTITY


func hat_offset_error() -> Vector2:
	return Vector2.ZERO


func hat_grip_gap() -> float:
	return 0.0


var _face_decal: Node3D
var _face_mat: StandardMaterial3D
var _face_tex := {}


func _build_face_expr() -> void:
	# AC-style 2D face sticker on the Head bone (Tripo has no blendshapes).
	# Texture swaps make idle / smile / cheer / sleep readable at arm's length.
	if not parts.has("head") or parts["head"] == null:
		return
	var head: Node3D = parts["head"]
	_eyelid_l = _make_eyelid("EyelidL")
	_eyelid_r = _make_eyelid("EyelidR")
	head.add_child(_eyelid_l)
	head.add_child(_eyelid_r)
	# Tripo/Mixamo Head bone (after model.y=PI): +X face-forward, +Y skull-up, +Z character-left.
	_eyelid_l.position = Vector3(0.155, 0.055, 0.034)
	_eyelid_r.position = Vector3(0.155, 0.055, -0.034)
	_eyelid_l.scale = Vector3(1.15, 0.04, 1.05)
	_eyelid_r.scale = Vector3(1.15, 0.04, 1.05)
	_eyelid_l.visible = false
	_eyelid_r.visible = false
	# Keep a tiny procedural mouth as fallback under the decal.
	_mouth = MeshInstance3D.new()
	_mouth.name = "MouthExpr"
	var mm := SphereMesh.new()
	mm.radius = 0.014
	mm.height = 0.008
	mm.radial_segments = 8
	mm.rings = 4
	_mouth.mesh = mm
	var mout := StandardMaterial3D.new()
	mout.albedo_color = Color(0.78, 0.32, 0.34)
	mout.roughness = 0.65
	mout.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mouth.material_override = mout
	_mouth.position = Vector3(0.130, -0.005, 0.0)
	_mouth.visible = false
	head.add_child(_mouth)
	# AC-style face plate: opaque QuadMesh locked to Head bone (no billboard).
	# Covers Tripo's baked eyes/mouth; texture swap = idle/smile/cheer/sleep.
	var plate := MeshInstance3D.new()
	plate.name = "FaceExprDecal"
	var q := QuadMesh.new()
	# Large enough to cover Tripo eye shells + mouth once centered on the face.
	q.size = Vector2(0.15, 0.19)
	plate.mesh = q
	_face_mat = StandardMaterial3D.new()
	_face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_face_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_face_mat.no_depth_test = true
	_face_mat.render_priority = 20
	_face_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	plate.material_override = _face_mat
	# QuadMesh faces +Z by default; yaw −90° maps that normal onto Head +X (face-out).
	# Tuned against v25_face_fit2: cover eyes+mouth; slight −Z recenters L/R.
	plate.position = Vector3(0.095, 0.048, -0.018)
	plate.rotation = Vector3(0.0, -PI / 2.0, 0.0)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.layers = 1 | 2
	head.add_child(plate)
	_face_decal = plate
	_face_tex = {
		"neutral": _load_face_tex("res://art/boy/face_expr_idle.png"),
		"idle": _load_face_tex("res://art/boy/face_expr_idle.png"),
		"smile": _load_face_tex("res://art/boy/face_expr_smile.png"),
		"cheer": _load_face_tex("res://art/boy/face_expr_cheer.png"),
		"sleep": _load_face_tex("res://art/boy/face_expr_sleep.png"),
	}
	blink_timer = rng.randf_range(2.0, 5.0)
	_apply_face_decal("smile")


func _load_face_tex(path: String) -> Texture2D:
	# Prefer imported resource; fall back to raw PNG so headless stills work
	# before Godot has written a .import file.
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path) as Texture2D
		if t != null:
			return t
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _apply_face_decal(kind: String) -> void:
	if _face_decal == null:
		return
	var key := kind
	if key == "neutral":
		key = "idle"
	var tex: Texture2D = _face_tex.get(key, _face_tex.get("smile", null))
	if _face_mat != null:
		_face_mat.albedo_texture = tex
		_face_mat.albedo_color = Color.WHITE
	_face_decal.visible = tex != null


func _make_eyelid(nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	# Flattened disc: covers Tripo's bulbous eye shells without reading as a beige ball.
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.028
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	# Match Tripo peach skin (albedo_color multiply is applied on the body mat).
	mat.albedo_color = Color(0.96, 0.82, 0.70)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true  # draw over protruding eye shells
	mat.render_priority = 12
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 | 2
	return mi


## expr: "smile" | "sleep" | "cheer" | "neutral" | "idle"
## Face sticker texture swap (AC-style). Soft disc blink on top when awake.
func set_face_expr(kind: String) -> void:
	expr = kind
	_set_eyes_closed(false)
	if kind == "sleep":
		blink_t = -1.0
		blink_timer = 9999.0
	elif blink_timer > 8.0:
		blink_timer = rng.randf_range(2.2, 4.5)
	_apply_face_decal(kind)
	# Sleep uses eyelid discs, never the upright AC plate (edge-on = fabric ribbon).
	if kind == "sleep" and _face_decal:
		_face_decal.visible = false


func _update_face(delta: float = 0.0) -> void:
	if _eyelid_l == null or _eyelid_r == null:
		return
	_set_eyes_closed(false)
	var sleeping := (act_kind in ["sun", "sleep", "seatlie"] and act_lie_k > 0.55) or expr == "sleep"
	var want := expr
	if react_kind == "cheer":
		want = "cheer"
	elif sleeping:
		want = "sleep"
	_apply_face_decal(want)
	blink_t = -1.0
	blink_timer = 9999.0
	if sleeping:
		# Supine: AC plate reads as a vertical ribbon through the face; soft lids do too
		# when Head +X points skyward. Hide both — nap forearm covers the eyes instead.
		if _face_decal:
			_face_decal.visible = false
			_face_decal.scale = Vector3.ZERO
		_eyelid_l.visible = false
		_eyelid_r.visible = false
	else:
		if _face_decal:
			_face_decal.scale = Vector3.ONE
		_eyelid_l.visible = false
		_eyelid_r.visible = false
	if _mouth:
		_mouth.visible = false


func debug_pose(kind: String, p := 1.0, tt := 0.3) -> Vector3:
	match kind:
		"idle":
			set_idle(); _tick(0.05)
			return Vector3.ZERO
		"walk":
			set_move(1.2); _tick(0.05)
			return Vector3.ZERO
		"throw":
			charge(p); start_throw(p); _tick(0.05)
			return Vector3.ZERO
		"sit", "sun", "sleep", "seat":
			return activity(kind if kind in ["sun", "sleep", "seat"] else "sun", 1.0, 1.0 if kind == "sleep" else 0.0, tt)
	return Vector3.ZERO
