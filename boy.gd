class_name Boy
extends Node3D
## v22 Tripo boy: AI-generated Mixamo-rigged kid (boy/boy.glb from art/boy/tripo/).
## Same public API as the old procedural Boy so main.gd / selftest / sim keep working.
## Hat is baked into the mesh (no hat physics). Face is baked (no expression morphs).

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
	_setup_parts()
	_setup_tree()
	_build_blob()
	_build_stone()
	_build_hat_proxy()
	_build_glasses_stub()
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


func _build_glasses_stub() -> void:
	glasses = Node3D.new()
	glasses.name = "Glasses"
	glasses.visible = false
	parts["head"].add_child(glasses)


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
		_to_idle()
		return
	anim = "react"
	anim_t = 0.0
	act_target = 1.0
	act_rate = 5.0
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
	# All rest aliases play the Tripo "sit" clip (or idle when standing)
	var play_clip := "sit"
	if sit_k < 0.05 and lie_k <= 0.0:
		play_clip = "idle"
	var L := float(clips.get(clip, clips["sit"])["length"])
	_play(play_clip, clampf(u, 0.0, 0.99) * float(clips["sit"]["length"]), 0.2)
	act_target = 1.0
	act_w = 1.0 if sit_k > 0.02 or lie_k > 0.0 else act_w
	act_rate = 8.0
	hat_s = 1.0 if lie_k > 0.7 else 0.0
	glasses.visible = kind == "sun" and lie_k > 0.5
	blob.visible = sit_k < 0.3 and lie_k <= 0.0
	show_stone(false)
	# main.gd already applies rest_lie_b / rest_sit_b — do not tip the mesh here
	model.rotation.x = 0.0
	# Sit-as-lie: drop the mesh in model space (main pins Boy origin so pelvis hits rest_lie)
	if kind in ["sun", "sleep", "seatlie"]:
		lie_settle = lerpf(0.0, 0.28, smoothstep(0.0, 1.0, lie_k))
	else:
		lie_settle = 0.0
	model.position = model_base + Vector3(0.0, -lie_settle, 0.0)
	_apply_mixer()
	# Live pelvis in boy space WITHOUT the settle (so main's rest_lie math stays stable)
	var pel := _live_pelvis() + Vector3(0.0, lie_settle, 0.0)
	if pel.y < 0.05:
		pel = Vector3(0.0, Island.SEAT_TOP, 0.0)
	return pel


func end_activity() -> void:
	hat_s = 0.0
	hat_hold = 0.0
	glasses.visible = false
	blob.visible = true
	model.rotation.x = 0.0
	lie_settle = 0.0
	model.position = model_base
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
	model.rotation.x = 0.0
	lie_settle = 0.0
	model.position = model_base


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
		walk_k = 1.0
		move_w = move_toward(move_w, 1.0, delta * 4.0)
		var dist := 0.0
		if has_prev:
			dist = Vector3(global_position.x - prev_pos.x, 0, global_position.z - prev_pos.z).length()
		prev_pos = global_position
		has_prev = true
		var stride := float(clips["run"]["stride"]) if run_k > 0.5 else float(clips["walk"]["stride"])
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

	_apply_mixer()
	_update_blob()


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
	return false


func settling() -> bool:
	return false


func hat_seat(s := -1.0) -> Transform3D:
	return Transform3D.IDENTITY


func hat_on_head() -> Transform3D:
	return Transform3D.IDENTITY


func hat_offset_error() -> Vector2:
	return Vector2.ZERO


func hat_grip_gap() -> float:
	return 0.0


func _update_face(_delta: float = 0.0) -> void:
	# Tripo face is baked — no morphs / expression swaps.
	pass


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
