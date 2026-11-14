class_name Boy
extends Node3D
## v25 flat-eye Tripo boy: Mixamo-rigged kid (boy/boy.glb from art/boy/flateyes/).
## Same public API as the old procedural Boy so main.gd / selftest / sim keep working.
## Straw hat: baked brim stays on the head mesh; a procedural hat reparents to the chest
## bone in the hammock (baked brim collapsed into the scalp). Face expressions =
## full-body albedo+normal+MR swaps from boy/tex/ (no runtime painting or masks).

signal released
signal footstep(side: int, running: bool)
signal foot_flat(side: int)

# ~1.35× chibi; authored sit/hammock clips assume this scale + FLOOR_OFFSET y.
const SCALE := 1.35
const FLOOR_OFFSET := 0.00837  # 0.0062 * 1.35 — matches alignment.json
## Drop-in Mixamo GLB path. Replace boy/boy.glb (same Mixamo bone names) without code changes.
## Optional override: boy/boy_override.glb wins when present (AC-style flat-eye regen, etc.).
const MODEL_PATH := "res://boy/boy.glb"
const MODEL_OVERRIDE_PATH := "res://boy/boy_override.glb"
const META := "res://boy/boy_meta.json"
const T_RELEASE := 0.55
## Blend into run clip once past a brisk walk (matches main WALK_MAX≈1.15 → RUN_SPEED≈2.7).
const RUN_FROM := 1.15
const RUN_TO := 2.05
const SIT_HIPS_Y := 0.248  # unscaled Mixamo sit hips (see process_tripo / smoke)
## Surface-name hints for a dedicated face material slot (eye/mouth texture swaps).
const FACE_SLOT_HINTS := ["face", "Face", "head", "Head", "skin_face", "FaceMat", "eye", "Eye"]

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
## "head" | "chest" | "face" | "beside" — hammock lie uses chest so fabric clears the brim.
var hat_mode := "head"
## Sand spot for lounger "beside" mode (optional).
var hat_beside_world := Vector3.ZERO
## Bind-pose local verts of residual crown/brim on the body (usually empty after split).
var _hat_skin_idxs: PackedInt32Array = PackedInt32Array()
var _chest_attach: BoneAttachment3D
var _scalp_cover: MeshInstance3D
var _hat_on_head_xf := Transform3D.IDENTITY
var _hat_blend := 0.0
var _hat_bind_orig: PackedVector3Array = PackedVector3Array()
## kind -> {albedo, normal, mr} ImageTextures preloaded from boy/tex/
var face_textures := {}

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
var expr := "idle"
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
var _boy_mats: Array[StandardMaterial3D] = []
var _boy_albedo_day := Color(1.0, 0.97, 0.93, 1.0)
var _boy_albedo_tex_day: Texture2D
var _boy_albedo_tex_sleep: Texture2D
var _eyes_closed_tex := false
## Soft eyelid MeshInstances / eye-shell morphs removed — flat-eye GLB uses albedo paints only.
var _eyelid_l: MeshInstance3D = null
var _eyelid_r: MeshInstance3D = null
var _mouth: MeshInstance3D = null
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
	model = _instantiate_boy_model()
	# Tripo/Mixamo faces +Z in glTF Y-up; game boy faces -Z like the old model
	model.rotation.y = PI
	model.scale = Vector3.ONE * SCALE
	var ground := float(meta.get("ground", 0.0))
	model.position.y = -ground * SCALE
	model_base = model.position
	add_child(model)
	skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
	ap = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_register_clip_aliases()
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
	_build_procedural_hat_fallback()
	_cache_hat_bind_verts()
	_load_face_albedos()
	set_face_expr("idle")
	release_stand = _probe_release("throw_stand")
	# crouch: clearly lower release so water entry is flatter than standing
	release_crouch = release_stand + Vector3(0.02, -0.14 * SCALE, 0.04)
	_apply_mixer()


## Load boy/boy_override.glb when present, else boy/boy.glb. Same Mixamo skeleton expected.
func _instantiate_boy_model() -> Node3D:
	var path := MODEL_PATH
	if ResourceLoader.exists(MODEL_OVERRIDE_PATH) or FileAccess.file_exists(ProjectSettings.globalize_path(MODEL_OVERRIDE_PATH)):
		path = MODEL_OVERRIDE_PATH
		print("Boy: using override GLB ", path)
	elif not ResourceLoader.exists(path):
		push_error("Boy: missing model at " + path)
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Boy: failed to load " + path)
		return Node3D.new()
	return packed.instantiate() as Node3D


## Duplicate gameplay-role aliases onto the AnimationPlayer so old call sites keep working.
## dig / lift_heavy stay as themselves — never aliased to sleep or stone-pick.
func _register_clip_aliases() -> void:
	if ap == null:
		return
	var aliases := {
		"standing_relax": "idle",
		"stroll": "walk",
		# Authoring GLB ships pitch_baseball as the throw clip.
		"throw_stand": "pitch_baseball",
		"throw_crouch": "pitch_baseball",
		"wave": "turn",
		"oops": "cheer",
		"jump": "idle",
	}
	var lib_name := &""
	var libs: Array = ap.get_animation_library_list()
	if libs.size() > 0:
		lib_name = libs[0]
	var lib: AnimationLibrary = ap.get_animation_library(lib_name)
	if lib == null:
		return
	for alias in aliases.keys():
		var src: String = aliases[alias]
		if ap.has_animation(alias):
			continue
		if not ap.has_animation(src):
			continue
		var anim_src: Animation = ap.get_animation(src)
		if anim_src == null:
			continue
		lib.add_animation(alias, anim_src.duplicate())
	# Ensure prop loop clips drop the duplicated last frame (authoring: first==last of enter).
	for n in ["bench_sit_idle", "log_sit_idle", "hammock_sleep"]:
		if not ap.has_animation(n):
			continue
		var a: Animation = ap.get_animation(n)
		if a == null:
			continue
		# 193 frames @ 24 fps → trim to 192/24 = 8.0 s.
		var trimmed := maxf(a.length - (1.0 / 24.0), a.length * 0.99)
		a.length = trimmed
		a.loop_mode = Animation.LOOP_LINEAR


func _force_loops() -> void:
	if ap == null:
		return
	for n in ["idle", "standing_relax", "walk", "run", "sit", "stroll", "look_around",
			"bench_sit_idle", "log_sit_idle", "hammock_sleep"]:
		if ap.has_animation(n):
			var a: Animation = ap.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR
	# stroll may be missing — AnimationTree uses walk for stroll seek


## Direct AnimationPlayer playback for authored prop clips (bypasses AnimationTree pose stack).
var prop_clip := ""
var prop_clip_loop := false


func play_prop_clip(clip: String, loop := false, fade := 0.0) -> void:
	if ap == null or not ap.has_animation(clip):
		push_warning("Boy: missing prop clip " + clip)
		return
	anim = "prop_clip"
	prop_clip = clip
	prop_clip_loop = loop
	act_kind = ""
	act_lie_k = 0.0
	act_w = 0.0
	act_target = 0.0
	react_kind = ""
	move_w = 0.0
	_walk_bob = 0.0
	hip_shift = Vector3.ZERO
	show_stone(false)
	if model:
		model.position = model_base
	if tree:
		tree.active = false
	ap.active = true
	var a: Animation = ap.get_animation(clip)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if fade > 0.0 and ap.current_animation != "":
		ap.play(clip, fade)
	else:
		ap.play(clip)
	ap.seek(0.0, true)
	ap.advance(0.0)
	if skel:
		skel.force_update_transform()


func prop_clip_time() -> float:
	if ap == null or prop_clip == "":
		return 0.0
	return ap.current_animation_position


func prop_clip_length() -> float:
	if ap == null or not ap.has_animation(prop_clip):
		return 0.0
	return ap.get_animation(prop_clip).length


func prop_clip_finished() -> bool:
	if prop_clip == "" or prop_clip_loop:
		return false
	if ap == null or not ap.is_playing():
		return prop_clip_time() >= prop_clip_length() - 0.02
	return prop_clip_time() >= prop_clip_length() - 0.02


func prop_clip_frame(fps := 24.0) -> int:
	return int(floor(prop_clip_time() * fps + 1e-4))


func seek_prop_clip(seconds: float) -> void:
	if ap == null or prop_clip == "":
		return
	var len := prop_clip_length()
	var t := clampf(seconds, 0.0, maxf(len - 0.001, 0.0))
	ap.seek(t, true)
	ap.advance(0.0)
	if skel:
		skel.force_update_transform()


func end_prop_clip(fade_to_idle := 0.2) -> void:
	prop_clip = ""
	prop_clip_loop = false
	if ap and fade_to_idle > 0.0 and ap.has_animation("idle"):
		ap.play("idle", fade_to_idle)
		ap.seek(0.0, true)
	set_idle()
	show_stone(true)
	if tree:
		tree.active = true


## Sit gameplay uses idle seed + additive L-sit (_apply_ergonomic_sit). Do NOT rewrite
## Mixamo sit clip keys to absolute eulers — that broke thigh_fwd on the flat-eye bind pose.
func _patch_ergonomic_sit_anim() -> void:
	pass


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
	# No alpha contact quad — Compatibility Bayer-dithers alpha into a hard square underfoot.
	# Real sun/moon shadow from the boy mesh (high bias + soft blur) grounds him instead.
	blob = MeshInstance3D.new()
	blob.name = "Blob"
	blob.visible = false
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Stub only — sit/lie toggles still reference blob.



func _build_stone() -> void:
	stone = MeshInstance3D.new()
	stone.name = "Stone"
	stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_hat_attach = BoneAttachment3D.new()
	_hat_attach.name = "HatAttach"
	_hat_attach.bone_name = B_HEAD
	skel.add_child(_hat_attach)
	_chest_attach = BoneAttachment3D.new()
	_chest_attach.name = "ChestAttach"
	_chest_attach.bone_name = "mixamorig_Spine2"
	skel.add_child(_chest_attach)
	hat = MeshInstance3D.new()
	hat.name = "Hat"
	hat.visible = false
	hat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hat_attach.add_child(hat)
	hat.position = Vector3(0, 0.08, 0)
	hat_mode = "head"


## Procedural straw hat used only when the baked brim is collapsed (chest/beside modes).
func _build_procedural_hat_fallback() -> void:
	if hat == null:
		return
	var HB = MeshBuilder.new()
	var straw := Color(0.90, 0.74, 0.45)
	var band := Color(0.55, 0.28, 0.18)
	for i in 12:
		var a0 := TAU * float(i) / 12.0
		var a1 := TAU * float(i + 1) / 12.0
		var c0 := Vector3(cos(a0) * 0.09, 0.10, sin(a0) * 0.09)
		var c1 := Vector3(cos(a1) * 0.09, 0.10, sin(a1) * 0.09)
		var top := Vector3(0, 0.16, 0)
		HB.face(c0, c1, top, straw, straw, straw, Vector3.UP)
		var b0 := Vector3(cos(a0) * 0.09, 0.02, sin(a0) * 0.09)
		var b1 := Vector3(cos(a1) * 0.09, 0.02, sin(a1) * 0.09)
		HB.face(b0, b1, c1, straw, straw, straw, Vector3(cos(a0), 0, sin(a0)))
		HB.face(b0, c1, c0, straw, straw, straw, Vector3(cos(a0), 0, sin(a0)))
		var r0 := Vector3(cos(a0) * 0.20, 0.02, sin(a0) * 0.20)
		var r1 := Vector3(cos(a1) * 0.20, 0.02, sin(a1) * 0.20)
		HB.face(b0, b1, r1, straw.darkened(0.05), straw.darkened(0.05), straw.darkened(0.05), Vector3.UP)
		HB.face(b0, r1, r0, straw.darkened(0.05), straw.darkened(0.05), straw.darkened(0.05), Vector3.UP)
	for i in 12:
		var a0 := TAU * float(i) / 12.0
		var a1 := TAU * float(i + 1) / 12.0
		var u0 := Vector3(cos(a0) * 0.095, 0.045, sin(a0) * 0.095)
		var u1 := Vector3(cos(a1) * 0.095, 0.045, sin(a1) * 0.095)
		var l0 := Vector3(cos(a0) * 0.095, 0.025, sin(a0) * 0.095)
		var l1 := Vector3(cos(a1) * 0.095, 0.025, sin(a1) * 0.095)
		HB.face(l0, l1, u1, band, band, band, Vector3(cos(a0), 0, sin(a0)))
		HB.face(l0, u1, u0, band, band, band, Vector3(cos(a0), 0, sin(a0)))
	hat.mesh = HB.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	hat.material_override = mat
	# Hidden while baked hat is on the head; shown when reparented to chest.
	hat.visible = false
	hat.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0))
	_hat_on_head_xf = hat.transform
	if _scalp_cover == null:
		_scalp_cover = MeshInstance3D.new()
		_scalp_cover.name = "ScalpCover"
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.10
		_scalp_cover.mesh = sm
		var scalp_mat := StandardMaterial3D.new()
		scalp_mat.albedo_color = Color(0.55, 0.38, 0.28)
		_scalp_cover.material_override = scalp_mat
		_scalp_cover.position = Vector3(0, 0.06, 0)
		_scalp_cover.visible = false
		_scalp_cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hat_attach.add_child(_scalp_cover)


## Snapshot baked brim verts so chest mode can collapse them into the scalp.
func _cache_hat_bind_verts() -> void:
	_ensure_skin_cache()
	_hat_bind_orig = PackedVector3Array()
	_hat_bind_orig.resize(_hat_skin_idxs.size())
	for k in _hat_skin_idxs.size():
		_hat_bind_orig[k] = _skin_verts[_hat_skin_idxs[k]]


func _set_baked_hat_collapsed(collapsed: bool) -> void:
	_ensure_skin_cache()
	if _hat_skin_idxs.is_empty() or _hat_bind_orig.is_empty():
		return
	var head_i := skel.find_bone(B_HEAD) if skel else -1
	var target := Vector3(0, 0.10, 0)
	if head_i >= 0:
		target = skel.get_bone_global_rest(head_i).origin + Vector3(0, 0.07, 0)
	for k in _hat_skin_idxs.size():
		var i: int = _hat_skin_idxs[k]
		if collapsed:
			_skin_verts[i] = _hat_bind_orig[k].lerp(target, 0.94)
		else:
			_skin_verts[i] = _hat_bind_orig[k]
	_write_skin_verts_to_mesh(_skin_verts)


func _hat_chest_local(face_tip: bool) -> Transform3D:
	if face_tip:
		return Transform3D(Basis.from_euler(Vector3(0.35, 0.2, 0.1)), Vector3(0.0, 0.06, 0.14))
	return Transform3D(Basis.from_euler(Vector3(1.15, 0.4, 0.25)), Vector3(0.0, 0.10, 0.12))


func _hat_beside_xf(beside_world: Vector3) -> Transform3D:
	var p := beside_world
	if p == Vector3.ZERO:
		p = hat_beside_world
	if p == Vector3.ZERO:
		p = global_position + Vector3(0.45, 0.04, 0.12)
	return Transform3D(Basis.from_euler(Vector3(0.15, 0.9, 0.4)), p)


func set_hat_mode(mode: String, beside_world: Vector3 = Vector3.ZERO) -> void:
	if hat == null or not is_instance_valid(hat):
		return
	if beside_world != Vector3.ZERO:
		hat_beside_world = beside_world
	hat_mode = mode
	if _scalp_cover:
		_scalp_cover.visible = mode != "head"
	if mode == "head":
		_set_baked_hat_collapsed(false)
		hat.visible = false
		if hat.get_parent() != _hat_attach:
			if hat.get_parent():
				hat.get_parent().remove_child(hat)
			_hat_attach.add_child(hat)
		hat.transform = _hat_on_head_xf
		_hat_blend = 0.0
	elif mode == "face" or mode == "chest":
		if _chest_attach == null:
			return
		_set_baked_hat_collapsed(true)
		hat.visible = true
		if hat.get_parent() != _chest_attach:
			if hat.get_parent():
				hat.get_parent().remove_child(hat)
			_chest_attach.add_child(hat)
		hat.transform = _hat_chest_local(mode == "face")
		_hat_blend = 1.0
	elif mode == "beside":
		_set_baked_hat_collapsed(true)
		hat.visible = true
		if hat.get_parent() != self:
			if hat.get_parent():
				hat.get_parent().remove_child(hat)
			add_child(hat)
		hat.global_transform = _hat_beside_xf(beside_world)
		_hat_blend = 1.0


## Hammock lie → procedural hat on chest; baked brim collapsed into scalp.
func sync_hat_lie(kind: String, lie_k: float) -> void:
	if hat == null or not is_instance_valid(hat) or _hat_attach == null:
		return
	var b := smoothstep(0.18, 0.85, lie_k)
	_hat_blend = b
	if b <= 0.001:
		set_hat_mode("head")
		return
	if kind == "sleep":
		set_hat_mode("chest" if b > 0.35 else "head")
		return
	if kind == "sun" and hat_beside_world != Vector3.ZERO and b > 0.5:
		set_hat_mode("beside", hat_beside_world)
		return
	set_hat_mode("head")


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
	face_fill.light_energy = 0.0
	face_fill.omni_range = 0.4
	face_fill.omni_attenuation = 1.4
	face_fill.shadow_enabled = false
	face_fill.light_specular = 0.0
	face_fill.visible = false
	face_fill.light_cull_mask = 0
	parts["head"].add_child(face_fill)
	face_fill.position = Vector3(0.0, -0.02, -0.1)
	# Cool moonlight rim — only on at night, opposite the fill so edges read without flattening him.
	_night_rim = OmniLight3D.new()
	_night_rim.name = "NightRim"
	_night_rim.light_color = Color(0.90, 0.92, 1.0)
	_night_rim.light_energy = 0.0
	_night_rim.omni_range = 0.75
	_night_rim.omni_attenuation = 1.2
	_night_rim.shadow_enabled = false
	_night_rim.light_specular = 0.0
	_night_rim.light_cull_mask = 1 << 1
	_night_rim.visible = false
	parts["head"].add_child(_night_rim)
	_night_rim.position = Vector3(0.0, 0.04, 0.12)
	# Kept for API compatibility; energy stays 0 (albedo tint / body fill greys the skin).
	_night_body = OmniLight3D.new()
	_night_body.name = "NightBody"
	_night_body.light_color = Color(0.90, 0.92, 1.0)
	_night_body.light_energy = 0.0
	_night_body.omni_range = 1.4
	_night_body.omni_attenuation = 0.85
	_night_body.shadow_enabled = false
	_night_body.light_specular = 0.0
	_night_body.light_cull_mask = 1 << 1
	_night_body.visible = false
	if parts.has("pelvis"):
		parts["pelvis"].add_child(_night_body)
		_night_body.position = Vector3(0.0, 0.12, -0.08)
	else:
		add_child(_night_body)
		_night_body.position = Vector3(0.0, 0.55, -0.1)


## Blend the character-only fill with the world night look. k=0 day, k=1 full night.
## moon_dir: world direction toward the moon disk (sun.global_basis.z); used to place the rim.
## v26: lights do the night look — do NOT tint albedo (that greys skin / blues sclera).
func set_night_k(k: float, moon_dir: Vector3 = Vector3.ZERO) -> void:
	k = clampf(k, 0.0, 1.0)
	# Mobile WebGL2: no boy OmniLights — each adds a Compatibility forward pass.
	if face_fill:
		face_fill.light_energy = 0.0
		face_fill.visible = false
		face_fill.light_cull_mask = 0
	if _night_rim:
		_night_rim.light_energy = 0.0
		_night_rim.light_specular = 0.0
		_night_rim.visible = false
		_night_rim.light_cull_mask = 0
	if _night_body:
		_night_body.light_energy = 0.0
		_night_body.light_specular = 0.0
		_night_body.visible = false
		_night_body.light_cull_mask = 0
	# Same world lights as the ground. Pale Tripo albedo outshines moonlit sand —
	# stronger night trim so boy/ground stays ≈ 1.0–1.4 (v26), not a bright key.
	# Pale Tripo albedo outshines cool moon sand — trim so boy/ground ≈ 1.0–1.4.
	var lum_scale := lerpf(1.0, 0.55, k)
	for mat in _boy_mats:
		if mat == null:
			continue
		mat.albedo_color = Color(
			_boy_albedo_day.r * lum_scale,
			_boy_albedo_day.g * lum_scale,
			_boy_albedo_day.b * lum_scale,
			1.0
		)
		mat.metallic_specular = lerpf(0.2, 0.04, k)
		mat.roughness = lerpf(0.78, 0.94, k)
		mat.emission_enabled = false
		mat.emission_energy_multiplier = 0.0
		mat.emission = Color(0, 0, 0, 1)


func _tune_boy_material() -> void:
	# Tripo embeds metallic=1 which blacks out the face under the brim. Drop metal only —
	# no emission (that washed the vest/skin/hat into pastels). Stay fully opaque.
	# Multi-surface GLBs: keep body mats stable; dedicate a face slot for expression swaps.
	if skel == null:
		return
	_face_mat = null
	_face_surf_i = -1
	_boy_mats.clear()
	for c in skel.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var nsurf: int = mi.mesh.get_surface_count()
		if nsurf < 1:
			continue
		_body_mi = mi
		# Soft directional silhouette (bias/blur in MobileQuality kill the flat-sandal contact plate).
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.transparency = 0
		# Layer 1 only — same lights as terrain (no private layer-2 key).
		mi.layers = 1
		# Prefer per-surface materials so a face slot can swap without touching clothes/hat.
		mi.material_override = null
		for si in nsurf:
			var src: Material = mi.get_active_material(si)
			if src == null:
				src = mi.mesh.surface_get_material(si)
			if src == null:
				continue
			var mat := src.duplicate() as StandardMaterial3D
			if mat == null:
				continue
			_harden_boy_mat(mat)
			mi.mesh.surface_set_material(si, mat)
			_boy_mats.append(mat)
			var is_face := _surface_looks_like_face(mi.mesh, si, nsurf)
			if is_face and _face_mat == null:
				_face_mat = mat
				_face_surf_i = si
				_boy_albedo_tex_day = mat.albedo_texture
			elif _boy_mat == null and not is_face:
				_boy_mat = mat
		# Single-surface Tripo: one mat is both body + face (expression paints whole albedo).
		if _face_mat == null:
			var only: Material = mi.mesh.surface_get_material(0)
			_face_mat = only as StandardMaterial3D
			_face_surf_i = 0
			if _face_mat:
				_boy_albedo_tex_day = _face_mat.albedo_texture
		if _boy_mat == null:
			_boy_mat = _face_mat
		break


func _harden_boy_mat(mat: StandardMaterial3D) -> void:
	mat.metallic = 0.0
	mat.metallic_specular = 0.2
	mat.roughness = 0.78
	mat.emission_enabled = false
	mat.emission_energy_multiplier = 0.0
	mat.emission = Color(0, 0, 0, 1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	# Expression normals (boy/tex) replace Tripo eye-bulge normals; scale 1.0.
	mat.normal_enabled = true
	mat.normal_scale = 1.0
	# glTF metallicRoughnessTexture: G=roughness, B=metallic (same ImageTexture).
	if mat.roughness_texture != null:
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	if mat.metallic_texture != null:
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	mat.albedo_color = _boy_albedo_day
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	mat.disable_receive_shadows = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED


## Heuristic: named face/head/eye surface, or surface 0 when multi-slot and name empty.
func _surface_looks_like_face(mesh: Mesh, si: int, nsurf: int) -> bool:
	var nm := ""
	if mesh is ArrayMesh:
		nm = (mesh as ArrayMesh).surface_get_name(si)
	for h in FACE_SLOT_HINTS:
		if nm.findn(h) >= 0:
			return true
	# AC-style regen often puts Face as surface 0 with Clothes/Hat after.
	if nsurf > 1 and si == 0 and nm.is_empty():
		return true
	return false


## Apply albedo + normal + metallic-roughness for one expression (required together).
func _set_face_albedo(kind: String) -> void:
	_apply_face_pack(kind)


func _apply_face_pack(kind: String) -> void:
	# Prefer the dedicated face slot when multi-surface; fall back to body mat.
	var target: StandardMaterial3D = _face_mat if _face_mat else _boy_mat
	if target == null:
		return
	var key := kind
	if key == "neutral" or key == "":
		key = "idle"
	var pack = face_textures.get(key, null)
	if pack == null:
		pack = face_textures.get("idle", null)
	if pack == null:
		return
	_eyes_closed_tex = (key == "sleep" or key == "cheer")
	var alb: Texture2D = pack.get("albedo", null) if typeof(pack) == TYPE_DICTIONARY else pack
	var nrm: Texture2D = pack.get("normal", null) if typeof(pack) == TYPE_DICTIONARY else null
	var mr: Texture2D = pack.get("mr", null) if typeof(pack) == TYPE_DICTIONARY else null
	if alb != null:
		target.albedo_texture = alb
	if nrm != null:
		target.normal_enabled = true
		target.normal_texture = nrm
		target.normal_scale = 1.0
	if mr != null:
		# Same glTF channel layout as the embedded RM map.
		target.roughness_texture = mr
		target.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		target.metallic_texture = mr
		target.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	if _face_mat != null and _face_mat != target:
		_face_mat.albedo_texture = target.albedo_texture
		_face_mat.normal_texture = target.normal_texture
		_face_mat.normal_enabled = target.normal_enabled
		_face_mat.normal_scale = target.normal_scale
		_face_mat.roughness_texture = target.roughness_texture
		_face_mat.roughness_texture_channel = target.roughness_texture_channel
		_face_mat.metallic_texture = target.metallic_texture
		_face_mat.metallic_texture_channel = target.metallic_texture_channel
	if _body_mi and _body_mi.mesh and _face_surf_i >= 0 \
			and _face_surf_i < _body_mi.mesh.get_surface_count():
		_body_mi.mesh.surface_set_material(_face_surf_i, target)


func _set_eyes_closed(closed: bool) -> void:
	if closed:
		_apply_face_pack("sleep")
	elif expr != "" and expr != "sleep":
		_apply_face_pack(expr)
	else:
		_apply_face_pack("idle")


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
		set_face_expr("idle")
		_to_idle()
		return
	anim = "react"
	anim_t = 0.0
	act_target = 1.0
	act_rate = 5.0
	# Good skip → cheer maps; other reacts keep a soft smile.
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
	# Hammock climb starts earlier so sit→legs-in→lie reads (was stuck in sit until 0.45).
	var full_lie := (lie_k > 0.18 and kind == "sleep") or (lie_k > 0.45 and kind in ["sun", "seatlie"])
	if sit_k < 0.05 and lie_k <= 0.0:
		play_clip = "idle"
		seek_len = float(clips["idle"]["length"])
	elif full_lie:
		play_clip = "idle"
		seek_len = float(clips["idle"]["length"])
		u = 0.0
	# Seated ergonomic path seeds from idle — don't flash the Mixamo sit clip (crosses legs /
	# braces hands behind). Full lie also freezes on idle.
	if (kind in ["seat", "sleep", "sun"] and sit_k > 0.02 and not full_lie) or full_lie:
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
	blob.visible = false
	show_stone(false)
	model.rotation.x = 0.0
	# lie_settle used to nudge model.position.y, but once rest_lie_b is applied that local +Y
	# is the head axis (along the bed), not world-up — so it slid him along the towel/hammock.
	# Height above the surface is owned by main's rest_lie.y only.
	lie_settle = 0.0
	model.position = model_base
	if full_lie:
		_seed_lie_from_sit()
		if kind == "sleep" and lie_k < 0.88:
			# Peak climb mid-way: sit-on-edge → swing legs in → settle lie.
			var climb_w := sin(clampf(lie_k, 0.0, 1.0) * PI)
			climb_w *= 1.0 - smoothstep(0.72, 0.92, lie_k)
			apply_hammock_climb(climb_w)
			_apply_lie_pose(kind, maxf(lie_k, 0.35), tt)
		else:
			_apply_lie_pose(kind, lie_k, tt)
		# Seek clears pose overrides — keep thighs planted on the lounger cushion.
		if lie_foot_plant and kind == "sun":
			plant_feet_on_plane(lie_foot_plane_point, lie_foot_plane_normal, lie_foot_plant_gap, true)
		# Hammock: hat moves to chest. Lounger: tip/beside. Sit: hat on head.
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
	blob.visible = false
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
	# Tip head/hat BACK toward the pillow end so the brim clears the fabric bed.
	_pose_abs("mixamorig_Neck", Vector3(0.28, 0.0, 0.0), w)
	_pose_abs("mixamorig_Head", Vector3(0.62 + breath * 0.02, 0.0, 0.0), w)
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


## Sit: plant wrists on mid-thighs so hands rest, not brace behind. Hands only —
## forearm overrides rubber-hose Tripo arms into noodles.
func _plant_hands_on_thighs(w: float) -> void:
	if skel == null or w < 0.05:
		return
	skel.force_update_transform()
	var face: Vector3 = -global_transform.basis.z.normalized()
	if model != null and is_instance_valid(model):
		face = model.global_transform.basis.z.normalized()
	var pairs := [
		["mixamorig_LeftHand", "mixamorig_LeftUpLeg", "mixamorig_LeftLeg"],
		["mixamorig_RightHand", "mixamorig_RightUpLeg", "mixamorig_RightLeg"],
	]
	for p in pairs:
		var hbi := skel.find_bone(p[0])
		var ubi := skel.find_bone(p[1])
		var kbi := skel.find_bone(p[2])
		if hbi < 0 or ubi < 0 or kbi < 0:
			continue
		var hip: Vector3 = lie_bone_world(p[1])
		var knee: Vector3 = lie_bone_world(p[2])
		# Rest on the top of the thigh — reads as hands-on-laps.
		var thigh_mid: Vector3 = hip.lerp(knee, 0.48) + face * 0.03 + Vector3.UP * 0.04
		var xf: Transform3D = skel.global_transform * skel.get_bone_global_pose(hbi)
		# Blend gently so we don't yank the wrist through the elbow.
		var blend := clampf(w * 0.75, 0.0, 0.85)
		var goal: Vector3 = xf.origin.lerp(thigh_mid, blend)
		var planted := Transform3D(xf.basis, goal)
		var local_xf: Transform3D = skel.global_transform.affine_inverse() * planted
		skel.set_bone_global_pose_override(hbi, local_xf, blend, true)
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
	plant_feet_soft(plane_point, plane_normal, gap, 0.12)


## Soft sole plant: only nudge feet that are already near the plane. Far feet hang/swing.
func plant_feet_soft(plane_point: Vector3, plane_normal: Vector3 = Vector3.UP, gap := 0.03, max_pull := 0.06) -> void:
	if skel == null:
		return
	plane_normal = plane_normal.normalized()
	skel.force_update_transform()
	for bone_name in [B_FOOT[0], B_FOOT[1]]:
		var bi := skel.find_bone(bone_name)
		if bi < 0:
			continue
		var xf: Transform3D = skel.global_transform * skel.get_bone_global_pose(bi)
		var g := (xf.origin - plane_point).dot(plane_normal)
		# Skip feet that would need a long rubber-hose pull.
		if absf(g - gap) > max_pull * 1.25:
			continue
		var pull := clampf(g - gap, -max_pull, max_pull)
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


## Upright chair/log/hammock sit: parallel horizontal thighs, vertical shins, no cross.
func _apply_ergonomic_sit(w: float) -> void:
	if skel == null or w <= 0.001:
		return
	var k := smoothstep(0.0, 1.0, w)
	# Flat-eye Mixamo: BOTH UpLegs take negative X (mirrored Y/Z only). Positive Left X
	# pointed the left thigh backward. Scanned: L/R (-1.55, ±0.30, -0.45) + Legs -1.72
	# → both thighs forward (align≈0.9), elev≈3°, opposite outward lateral, shins down.
	_pose_abs("mixamorig_LeftUpLeg", Vector3(-1.55, 0.30, -0.45), k)
	_pose_abs("mixamorig_RightUpLeg", Vector3(-1.55, -0.30, -0.45), k)
	_pose_abs("mixamorig_LeftLeg", Vector3(-1.72, 0.0, 0.0), k)
	_pose_abs("mixamorig_RightLeg", Vector3(-1.72, 0.0, 0.0), k)
	_pose_abs("mixamorig_LeftFoot", Vector3(-0.08, 0.0, -0.02), k * 0.8)
	_pose_abs("mixamorig_RightFoot", Vector3(-0.08, 0.0, 0.02), k * 0.8)
	# Upright back.
	_pose_abs("mixamorig_Spine", Vector3(-0.02, 0.0, 0.0), k * 0.45)
	_pose_abs("mixamorig_Spine1", Vector3(-0.01, 0.0, 0.0), k * 0.35)
	_pose_abs("mixamorig_Spine2", Vector3(0.0, 0.0, 0.0), k * 0.25)
	# Hands resting on mid-thighs.
	_pose_abs("mixamorig_LeftArm", Vector3(0.70, 0.55, -0.55), k)
	_pose_abs("mixamorig_RightArm", Vector3(0.70, -0.55, 0.55), k)
	_pose_abs("mixamorig_LeftForeArm", Vector3(-1.05, 0.20, 0.08), k)
	_pose_abs("mixamorig_RightForeArm", Vector3(-1.05, -0.20, -0.08), k)
	_pose_abs("mixamorig_LeftHand", Vector3(0.12, 0.06, 0.18), k)
	_pose_abs("mixamorig_RightHand", Vector3(0.12, -0.06, -0.18), k)
	skel.force_update_transform()
	_plant_hands_on_thighs(k)

## Bake the current skeleton pose into a static ArrayMesh so stills show deformation on
## drivers that leave the skinned mesh at bind pose (llvmpipe Compatibility).
func bake_pose_mesh() -> void:
	_ensure_skin_cache()
	if skel == null or _body_mi == null or _skin_verts.is_empty():
		return
	# Keep chest-mode collapse in the skinned bake so the baked brim doesn't reappear.
	if hat_mode != "head":
		_set_baked_hat_collapsed(true)
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
	# Keep the LIVE expression albedo (face paint), not the bind-pose day texture.
	var live_mat: Material = null
	if _face_mat != null:
		live_mat = _face_mat
	elif _boy_mat != null:
		live_mat = _boy_mat
	elif _body_mi.get_active_material(0) != null:
		live_mat = _body_mi.get_active_material(0)
	elif _body_mesh_orig is ArrayMesh:
		live_mat = (_body_mesh_orig as ArrayMesh).surface_get_material(0)
	if live_mat:
		baked.surface_set_material(0, live_mat)
	_body_mi.mesh = baked
	_body_mi.skeleton = NodePath()
	_body_mi.skin = null
	_pose_baked = true
	# Re-assert current expression maps on the baked material.
	if expr != "":
		_apply_face_pack(expr)


func restore_pose_mesh() -> void:
	if not _pose_baked or _body_mi == null:
		return
	_body_mi.mesh = _body_mesh_orig
	_body_mi.skeleton = _body_skel_path
	_body_mi.skin = _body_skin_orig
	_pose_baked = false
	# Re-apply chest collapse after restoring the pristine bind mesh.
	if hat_mode != "head":
		_set_baked_hat_collapsed(true)
	else:
		_set_baked_hat_collapsed(false)


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


## Sample straw-hat verts in world space (split hat mesh, else residual baked idxs).
func hat_sample_world(max_samples := 160) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if hat != null and is_instance_valid(hat) and hat.mesh != null and hat.visible:
		var arr: Array = hat.mesh.surface_get_arrays(0)
		if not arr.is_empty():
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if not verts.is_empty():
				var xf: Transform3D = hat.global_transform
				var step: int = maxi(1, verts.size() / maxi(max_samples, 1))
				for i in range(0, verts.size(), step):
					out.append(xf * verts[i])
				if out.size() >= 8:
					return out
	_ensure_skin_cache()
	if skel == null or _hat_skin_idxs.is_empty():
		return out
	skel.force_update_transform()
	var bone_xf: Array[Transform3D] = []
	bone_xf.resize(skel.get_bone_count())
	for bi in skel.get_bone_count():
		bone_xf[bi] = skel.global_transform * skel.get_bone_global_pose(bi) * skel.get_bone_global_rest(bi).affine_inverse()
	var n: int = _hat_skin_idxs.size()
	var step2: int = maxi(1, n / maxi(max_samples, 1))
	for k in range(0, n, step2):
		var i: int = _hat_skin_idxs[k]
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
		if wsum < 0.01:
			continue
		out.append(skinned / wsum)
	return out


func throw_stance() -> Array:
	return []


func _throw_clip() -> String:
	# Meta key in boy_meta.json (has t_charge / t_release). Playback resolves to pitch_baseball.
	return "throw_crouch" if stance == "crouch" else "throw_stand"


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
	# aliases — dig/lift_heavy intentionally omitted (not sleep / stone-pick).
	var map := {
		"stroll": "walk",
		"throw_stand": "pitch_baseball", "throw_crouch": "pitch_baseball",
		"wave": "turn", "oops": "cheer", "standing_relax": "idle", "jump": "idle",
		"sun_sit": "sit", "sun_lie": "sit", "sun_rest": "sit", "sun_up": "sit", "sun_stand": "idle",
		# Authored hammock/bench/log clips — resolve only when present.
		"hammock_sit": "hammock_enter", "hammock_lie": "hammock_sleep",
		"hammock_sleep": "hammock_sleep", "hammock_up": "hammock_exit", "hammock_stand": "idle",
		"seat_sit": "bench_sit_idle", "seat_rest": "bench_sit_idle",
		"seat_lie": "bench_sit_idle", "seat_nap": "bench_sit_idle",
		"seat_up": "bench_sit_exit", "seat_stand": "idle",
	}
	var a: String = map.get(name, "idle")
	if ap.has_animation(a):
		return a
	# Fallbacks when a prop clip is missing.
	if ap.has_animation("sit"):
		return "sit"
	return "idle" if ap.has_animation("idle") else name


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
		# Frame-rate independent speed smoothing — avoids walk↔run blend pops on hitch/ProMotion.
		speed_s = lerpf(speed_s, move_speed, 1.0 - exp(-delta * 12.0))
		run_k = 0.0 if pivoting else smoothstep(RUN_FROM, RUN_TO, speed_s)
		# Light stick → stroll (soft), then walk. Keep walk_k for mix amount.
		walk_k = clampf(smoothstep(0.35, 1.05, speed_s), 0.0, 1.0)
		move_w = move_toward(move_w, 1.0, delta * 4.0)
		var dist := 0.0
		if has_prev:
			dist = Vector3(global_position.x - prev_pos.x, 0, global_position.z - prev_pos.z).length()
		prev_pos = global_position
		has_prev = true
		# Blend stride with run_k so walk→run doesn't jump the phase rate at 0.5.
		var stride := lerpf(float(clips["walk"]["stride"]), float(clips["run"]["stride"]), run_k)
		# Drive phase from smoothed speed (matches anim to locomotion). Position delta
		# only clamps hitch overshoot — never leads, so interp/display lag can't skate.
		var dphase: float
		if pivoting or speed_s < 0.04:
			dphase = delta / maxf(float(clips["walk"]["length"]), 0.2)
		else:
			dphase = (speed_s * delta) / maxf(stride, 0.05)
			if dist > 1e-5:
				dphase = minf(dphase, dist / maxf(stride, 0.05) * 1.15)
		dphase = minf(dphase, 0.18)
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

	if anim == "prop_clip" or prop_clip != "":
		# Authored bench/log/hammock clips: AnimationPlayer only, no tree/pose stack.
		if tree:
			tree.active = false
		if ap and not ap.active:
			ap.active = true
		_update_blob()
		_update_face(delta)
		return
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
	# Slight UP bob on mid-swing only — never dip the root below model_base
	# (downward bob read as "buried in the island" while the stick was held).
	var want_bob := absf(sin(phase * TAU)) * bob_amp * 0.55 if moving else 0.0
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
	blob.visible = false


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


const SPOT_RATE := 2.8
const STEER_GRIP := 4.0
const STEER_TOP := 5.5

static func spot_turn(face: float, want: float, rate: float, delta: float) -> Array:
	var need := wrapf(want - face, -PI, PI)
	# Ease into the pivot (weight settles on the planted foot) then finish cleanly.
	var top := minf(SPOT_RATE, 0.9 + absf(need) * 2.2)
	rate = move_toward(rate, top, delta * 9.0)
	var stp := minf(absf(need), rate * delta)
	return [face + signf(need) * stp, rate]


static func wants_spot_turn(need: float, speed: float) -> bool:
	# Standing / near-stop only. Never steal a walking stick push.
	return speed < 0.18 and absf(need) > 1.25


static func move_turn(face: float, want: float, speed: float, delta: float) -> Array:
	var need := wrapf(want - face, -PI, PI)
	var top := minf(STEER_TOP, STEER_GRIP / maxf(speed, 0.35))
	var stp := minf(absf(need), minf(top, absf(need) * 8.0) * delta)
	# Heavier speed kill on sharp corners — reads as weight, not ice-skate.
	return [face + signf(need) * stp, 1.0 - 0.82 * smoothstep(0.45, 1.55, absf(need))]


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


var _face_decal: Node3D = null  # removed — opaque plate rejected
var _face_mat: StandardMaterial3D = null
var _face_surf_i := -1  # mesh surface index for map swaps (−1 = whole body)
## Legacy alias: kind -> albedo Texture2D (selftest / older probes).
var _face_alb := {}
var _face_normal_flat: Texture2D = null  # unused — expression normals replace Tripo maps
var _idle_smile_t := 0.0  # standing idle smile pulse timer


func _build_face_expr() -> void:
	# Texture-swap only — no plates, lid discs, or runtime paints.
	_face_decal = null
	_mouth = null
	_eyelid_l = null
	_eyelid_r = null
	blink_timer = 9999.0
	blink_t = -1.0


func _load_face_tex(path: String) -> Texture2D:
	# Always read pixels from disk so rebakes aren't stuck behind .import cache.
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _load_face_albedos() -> void:
	# Preload verified offline packs: albedo + normal + MR per expression.
	# cheer/sleep share one closed-eye normal and one closed-eye MR (identical sources).
	var root := "res://boy/tex/"
	var closed_n: Texture2D = _load_face_tex(root + "normal_closed.jpg")
	if closed_n == null:
		closed_n = _load_face_tex(root + "normal_cheer.jpg")
	var closed_mr: Texture2D = _load_face_tex(root + "mr_closed.jpg")
	if closed_mr == null:
		closed_mr = _load_face_tex(root + "mr_cheer.jpg")
	face_textures = {}
	_face_alb = {}
	# One normal/MR base (idle) + closed-eye set — avoid four full 2K PBR packs in VRAM.
	var idle_n: Texture2D = _load_face_tex(root + "normal_idle.jpg")
	var idle_mr: Texture2D = _load_face_tex(root + "mr_idle.jpg")
	for kind in ["idle", "smile", "cheer", "sleep"]:
		var alb: Texture2D = _load_face_tex(root + "albedo_%s.jpg" % kind)
		if alb == null:
			alb = _load_face_tex(root + "albedo_%s.png" % kind)
		var nrm: Texture2D
		var mr: Texture2D
		if kind == "cheer" or kind == "sleep":
			nrm = closed_n if closed_n else idle_n
			mr = closed_mr if closed_mr else idle_mr
		else:
			# smile shares idle normal/MR (albedo carries the expression).
			nrm = idle_n
			mr = idle_mr
		if alb == null:
			alb = _boy_albedo_tex_day
		face_textures[kind] = {"albedo": alb, "normal": nrm, "mr": mr}
		_face_alb[kind] = alb
	face_textures["neutral"] = face_textures["idle"]
	_face_alb["neutral"] = _face_alb.get("idle", null)
	# Apply idle pack immediately so first frame isn't the Tripo ghost-eye maps.
	_apply_face_pack("idle")


func _cache_eye_shell_verts() -> void:
	pass


func _hard_sink_eye_shells(_closed: bool) -> void:
	pass


func _set_eye_shells_closed(closed: bool) -> void:
	_set_eyes_closed(closed)


func _apply_brow_offsets(_kind: String) -> void:
	pass


func _write_skin_verts_to_mesh(verts: PackedVector3Array) -> void:
	if _body_mi == null or _pose_baked:
		return
	if _body_arrays_orig.is_empty():
		return
	var arrays: Array = _body_arrays_orig.duplicate(true)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var fmt: int = 0
	if _body_mesh_orig is ArrayMesh:
		fmt = (_body_mesh_orig as ArrayMesh).surface_get_format(0)
	var mat: Material = null
	if _body_mesh_orig is ArrayMesh:
		mat = (_body_mesh_orig as ArrayMesh).surface_get_material(0)
	var rebuilt := ArrayMesh.new()
	rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	if mat:
		rebuilt.surface_set_material(0, mat)
	_body_mi.mesh = rebuilt


func _apply_lid_discs(_kind: String) -> void:
	pass


## expr: "smile" | "sleep" | "cheer" | "neutral" | "idle"
## Swaps albedo + normal + MR together — no runtime painting.
func set_face_expr(kind: String) -> void:
	expr = kind
	blink_t = -1.0
	blink_timer = 9999.0
	_apply_face_pack(kind)


func _update_face(delta: float = 0.0) -> void:
	var sleeping := (act_kind in ["sun", "sleep", "seatlie"] and act_lie_k > 0.55) \
			or (expr == "sleep" and act_kind in ["sun", "sleep", "seatlie"])
	var want := "idle"
	if react_kind == "cheer":
		want = "cheer"
	elif sleeping:
		want = "sleep"
	elif anim == "move" and move_w > 0.25:
		# Walking happily.
		want = "smile"
	elif expr == "smile" or expr == "cheer" or expr == "sleep":
		want = expr
	else:
		# Standing idle: soft smile pulse every few seconds.
		_idle_smile_t += delta
		if _idle_smile_t > 4.5 and _idle_smile_t < 6.2:
			want = "smile"
		elif _idle_smile_t >= 6.2:
			_idle_smile_t = 0.0
			want = "idle"
		else:
			want = "idle"
	_apply_face_pack(want)
	blink_t = -1.0
	blink_timer = 9999.0


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
