class_name Boy
extends Node3D
## v6 boy: a skinned MakeHuman-based teen (boy/boy.glb, built and animated by art/boy/*.py in Blender)
## driven by an AnimationTree that is used as a mixer: every clip is seeked explicitly each frame.
##  - locomotion: idle / walk / run, the gait phase advances with the distance the node really moved
##    (stride-matched, so planted feet never slide whoever moves the boy)
##  - actions: two crossfading slots (throws, cheer / oops, resting clips)
##  - resting poses are seeked by main.gd's progress values; their pelvis offsets come from the
##    exported tracks so main.gd can place the boy in the same frame (activity()).

signal released
signal footstep(side: int, running: bool)

const SCALE := 0.85
const MODEL := preload("res://boy/boy.glb")
const META := "res://boy/boy_meta.json"
const T_RELEASE := 0.15      # stone leaves the hand this long after start_throw()
const RUN_FROM := 1.35       # walk -> run blend band (m/s)
const RUN_TO := 2.2

var parts := {}
var anim := "idle"   # idle | move | charge | throw | react | activity
var anim_t := 0.0
var stance := "stand"   # stand | crouch (throwing stance)
var hat_mode := "head"   # head | chest | ground
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
var face_mat: ShaderMaterial
var hat: Node3D
var glasses: Node3D
var stone: Node3D
var blob: MeshInstance3D
var hat_head_xf: Transform3D
var hat_head_parent: Node3D
var chest_att: BoneAttachment3D

var t := 0.0
var t_idle := 0.0
var phase := 0.0
var move_w := 0.0
var run_k := 0.0
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
var expr := "smile"
var rng := RandomNumberGenerator.new()
var frozen := false
# turning pivots about the planted foot: the root yaws about its own origin, which would drag a planted
# foot sideways, so the model is shifted (world-space offset, bled back to zero) to keep that contact put
var model_base := Vector3.ZERO
var plant_off := Vector3.ZERO
var plant_prev_yaw := 0.0
var plant_lag := 0.0
var prev_at: Array[Variant] = [null, null]
var turn_lean := 0.0
var settle_ph := 0.0
var contacts: Array = []      # per side: [foot bone, heel offset, ball bone, toe offset]
# foot locking: while a heel / toe pad is down, the leg is bent (two-bone IK) so that point and the foot's
# heading stay fixed in the world, whatever the walk / run blend, the stride change or a turn would do
# to it; the correction (offset and yaw about the ankle, skeleton space) bleeds off once the foot lifts
var legs: Array = []          # per side: [thigh, calf, foot, ball] bone indices
var lock_c: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var lock_yaw: Array[float] = [0.0, 0.0]
var lock_on: Array[bool] = [false, false]
var lock_prev: Array = [null, null]   # last frame's corrected [heel, toe] world points and foot heading
var lock_pos := Vector3.ZERO
var lock_enabled := true
var pivot_w: Array[float] = [0.0, 0.0]
var step_t: Array[float] = [-1.0, -1.0]
var steps_taken := 0
var step_from: Array = [[Vector3.ZERO, 0.0], [Vector3.ZERO, 0.0]]
const PIVOT_YAW := 0.45
const TURN_MAX := 12.0
const STEP_AT := 0.15        # skeleton units (~13 cm)
const STEP_DUR := 0.16
const STEP_LIFT := 0.06
const PIVOT_LIFT := 0.3

func _ready() -> void:
	rng.seed = 7
	process_priority = 10   # after main.gd has moved / posed us this frame
	meta = JSON.parse_string(FileAccess.get_file_as_string(META))
	clips = meta["clips"]
	model = MODEL.instantiate()
	model.rotation.y = PI
	model.scale = Vector3.ONE * SCALE
	model.position.y = -float(meta["ground"]) * SCALE
	model_base = model.position
	add_child(model)
	skel = model.find_child("Skeleton3D") as Skeleton3D
	for sd in ["l", "r"]:
		var fb := skel.find_bone("foot_" + sd)
		var bb := skel.find_bone("ball_" + sd)
		var fr := skel.get_bone_global_rest(fb)
		var br := skel.get_bone_global_rest(bb)
		var g := float(meta["ground"])
		contacts.append([fb, fr.affine_inverse() * Vector3(fr.origin.x, g, fr.origin.z - 0.035),
			bb, br.affine_inverse() * Vector3(br.origin.x, g, br.origin.z + 0.02)])
		legs.append([skel.find_bone("thigh_" + sd), skel.find_bone("calf_" + sd), fb, bb])
	_setup_materials()
	_setup_parts()
	_setup_tree()
	_build_blob()
	_build_gait_tables()
	release_stand = _probe_release("throw_stand")
	release_crouch = _probe_release("throw_crouch")
	_apply_mixer()

# ------------------------------------------------------------------ setup

func _mat(col: Color, kind: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/boy.gdshader")
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("kind", kind)
	return m

func _setup_materials() -> void:
	# albedo per Blender material name; kinds: 0 skin, 1 cloth, 2 hair, 3 straw, 4 props
	var look := {
		"skin": [Color(0.90, 0.66, 0.52), 0], "tank": [Color(0.95, 0.94, 0.90), 1],
		"vest": [Color(0.80, 0.27, 0.22), 1], "shorts": [Color(0.96, 0.80, 0.36), 1],
		"hair": [Color(0.30, 0.20, 0.14), 2], "sandal": [Color(0.36, 0.60, 0.64), 1],
		"strap": [Color(0.95, 0.93, 0.88), 1], "hat": [Color(0.92, 0.80, 0.55), 3],
		"band": [Color(0.78, 0.25, 0.20), 1], "lens": [Color(0.08, 0.09, 0.11), 4],
		"stone": [Color(0.55, 0.56, 0.58), 4],
	}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi.mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var n := src.resource_name if src else ""
			if not look.has(n):
				continue
			var m := _mat(look[n][0], look[n][1])
			mi.set_surface_override_material(i, m)
			if n == "skin":
				face_mat = m
		if mi.name in ["Glasses", "Stone"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _setup_parts() -> void:
	for att: BoneAttachment3D in skel.find_children("*", "BoneAttachment3D", false, false):
		for c in att.get_children():
			match String(c.name):
				"Hat": hat = c
				"Glasses": glasses = c
				"Stone": stone = c
	hat_head_parent = hat.get_parent()
	hat_head_xf = hat.transform
	glasses.visible = false
	for b in ["head", "pelvis", "spine_03"]:
		var a := BoneAttachment3D.new()
		a.name = "att_" + b
		a.bone_name = b
		skel.add_child(a)
		parts[b] = a
	chest_att = parts["spine_03"]

func _anim_node(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n

func _setup_tree() -> void:
	var ap := model.find_child("AnimationPlayer") as AnimationPlayer
	bt = AnimationNodeBlendTree.new()
	var x := 0.0
	for pair in [["idle", "idle"], ["walk", "walk"], ["run", "run"], ["a", "idle"], ["b", "idle"]]:
		bt.add_node(pair[0], _anim_node(pair[1]), Vector2(0, x))
		bt.add_node(pair[0] + "_s", AnimationNodeTimeSeek.new(), Vector2(200, x))
		bt.connect_node(pair[0] + "_s", 0, pair[0])
		x += 120.0
	bt.add_node("wr", AnimationNodeBlend2.new(), Vector2(400, 100))
	bt.connect_node("wr", 0, "walk_s")
	bt.connect_node("wr", 1, "run_s")
	bt.add_node("move", AnimationNodeBlend2.new(), Vector2(600, 0))
	bt.connect_node("move", 0, "idle_s")
	bt.connect_node("move", 1, "wr")
	bt.add_node("ab", AnimationNodeBlend2.new(), Vector2(400, 400))
	bt.connect_node("ab", 0, "a_s")
	bt.connect_node("ab", 1, "b_s")
	bt.add_node("act", AnimationNodeBlend2.new(), Vector2(800, 200))
	bt.connect_node("act", 0, "move")
	bt.connect_node("act", 1, "ab")
	bt.connect_node("output", 0, "act")
	tree = AnimationTree.new()
	tree.name = "Mixer"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	tree.tree_root = bt
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true

## soft contact shadow on the ground under the kid
func _build_blob() -> void:
	blob = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.52)
	q.orientation = PlaneMesh.FACE_Y
	blob.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/blob.gdshader")
	blob.material_override = m
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blob)

## stone position (boy space) on the release frame of a throw clip
func _probe_release(clip: String) -> Vector3:
	_set_slot(0, clip, float(clips[clip]["t_release"]))
	act_w = 1.0
	ab_w = 0.0
	_apply_mixer()
	# the stone's BoneAttachment3D sits exactly on the hand bone
	var hand := skel.get_bone_global_pose(skel.find_bone("hand_r"))
	act_w = 0.0
	var centre := (stone as MeshInstance3D).get_aabb().get_center()
	return model.transform * (hand * (stone.transform * centre))

# ------------------------------------------------------------------ coordinates

## Blender armature space (exported tracks) -> boy space
func b2g(v: Array) -> Vector3:
	return Vector3(-float(v[0]), float(v[2]) - float(meta["ground"]), float(v[1])) * SCALE

func _track(clip: String, key: String, u: float) -> Vector3:
	var arr: Array = clips[clip][key]
	var f := clampf(u, 0.0, 1.0) * float(arr.size() - 1)
	var i := mini(int(f), arr.size() - 2)
	return b2g(arr[i]).lerp(b2g(arr[i + 1]), f - float(i))

# ------------------------------------------------------------------ public API

func set_idle() -> void:
	if anim == "charge" or anim == "move":
		_to_idle()

func set_move(speed: float) -> void:
	move_speed = speed
	if speed > 0.05 and (anim == "idle" or anim == "react"):
		if anim != "move" and move_w < 0.05:
			phase = 0.31   # passing pose: left foot under the hips, right swinging past it
		anim = "move"
		stopping = false
		act_target = 0.0
		act_rate = 8.0

func charge(p: float) -> void:
	if anim != "charge":
		# a cheer / oops may still be showing: crossfade out of it instead of cutting
		var fade := 0.0 if act_w < 0.05 else 0.3
		anim = "charge"
		anim_t = 0.0
		act_target = 1.0
		# kneeling down takes a moment; stepping into the standing set-up is quick
		act_rate = 3.2 if stance == "crouch" else 6.0
		_play(_throw_clip(), 0.0, fade, fade > 0.0)
	power = p

func start_throw(p: float) -> void:
	throw_power = p
	anim = "throw"
	anim_t = 0.0
	did_release = false
	act_target = 1.0
	_play(_throw_clip(), float(clips[_throw_clip()]["t_charge"]), 0.08, true)

func react(kind: String) -> void:
	react_kind = kind
	if kind == "":
		_to_idle()
		return
	anim = "react"
	anim_t = 0.0
	act_target = 1.0
	act_rate = 5.0
	_play("cheer" if kind == "cheer" else "oops", 0.0, 0.25)

func show_stone(v: bool) -> void:
	stone.visible = v

## world-space heel (ankle) and ball joints of one foot (0 left, 1 right), for footprints
func foot_points(side: int) -> Array:
	var sx := "_l" if side == 0 else "_r"
	var heel := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("foot" + sx)).origin
	var ball := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("ball" + sx)).origin
	return [heel, ball]

## kind: "sleep" | "sun" | "seat" | "seatlie"; sit_k: 0 stand -> 1 seated; lie_k: 0 seated -> 1 lying ("seat": 1 =
## sitting idle; "seatlie": lying back along the bench / log), tt counted from when it started.
## Returns the pelvis in boy space.
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
		clip = "seat_nap"
		u = fposmod(tt, 4.0) / 4.0
	elif kind == "seat" and lie_k >= 1.0:
		clip = "seat_rest"
		u = fposmod(tt, 4.0) / 4.0
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
	var L := float(clips[clip]["length"])
	# the sitting idle loop can be mid foot-swing when he gets up: blend out of it
	var from_loop: bool = slot_clip[cur_slot] in ["seat_rest", "seat_nap"] and clip != slot_clip[cur_slot]
	_play(clip, u * L, 0.25 if kind.begins_with("seat") and from_loop else 0.0)
	act_target = 1.0
	act_w = 1.0 if sit_k > 0.02 or lie_k > 0.0 else act_w
	act_rate = 8.0
	hat_mode = "head"
	if kind == "seatlie" and lie_k > 0.55:
		hat_mode = "face"
	elif lie_k > 0.6 and not kind.begins_with("seat"):
		hat_mode = "chest" if kind == "sleep" else "ground"
	glasses.visible = kind == "sun" and lie_k > 0.5
	blob.visible = sit_k < 0.3 and lie_k <= 0.0
	if kind == "sleep" or kind == "seatlie":
		expr = "sleep" if lie_k > 0.7 else "smile"
	else:
		expr = "relax" if lie_k > 0.5 else "smile"
	show_stone(false)
	return _track(clip, "pelvis", u)

func end_activity() -> void:
	hat_mode = "head"
	glasses.visible = false
	blob.visible = true
	if act_frames == 0 and pre_act.size() == 7:
		# probed and released in the same frame (main.gd measures the seated pelvis): change nothing
		anim = pre_act[0]; act_w = pre_act[1]; act_target = pre_act[2]
		slot_clip.assign(pre_act[3]); slot_t.assign(pre_act[4]); cur_slot = pre_act[5]; ab_w = pre_act[6]
		_set_slot(0, slot_clip[0], slot_t[0])
		_set_slot(1, slot_clip[1], slot_t[1])
		expr = "smile"
		return
	# the stand-up clips end on the idle pose at t = 0
	_to_idle()
	act_w = 0.0
	has_prev = false
	show_stone(true)

func throw_stance() -> Array:
	return []

# ------------------------------------------------------------------ mixer

func _throw_clip() -> String:
	return "throw_crouch" if stance == "crouch" else "throw_stand"

func _to_idle() -> void:
	anim = "idle"
	act_target = 0.0
	act_rate = 6.0
	t_idle = 0.0
	expr = "smile"

func _set_slot(i: int, clip: String, time: float) -> void:
	if clip == "":
		return
	if slot_clip[i] != clip:
		slot_clip[i] = clip
		(bt.get_node("a" if i == 0 else "b") as AnimationNodeAnimation).animation = clip
	slot_t[i] = time

## play `clip` at `time` in the action slots; a different clip (or `jump`) crossfades over `fade` seconds
func _play(clip: String, time: float, fade: float, jump := false) -> void:
	if slot_clip[cur_slot] == clip and not jump:
		slot_t[cur_slot] = time
		return
	if fade <= 0.0:
		_set_slot(cur_slot, clip, time)
		ab_w = float(cur_slot)
		return
	cur_slot = 1 - cur_slot
	_set_slot(cur_slot, clip, time)
	ab_rate = 1.0 / fade

func _process(delta: float) -> void:
	if frozen:
		return
	_tick(delta)

func _tick(delta: float) -> void:
	t += delta
	anim_t += delta
	if anim == "activity":
		act_frames += 1
	# ground speed from the node's own motion (every mover gets planted feet)
	var gp := global_position
	var moved := Vector3.ZERO
	if has_prev:
		moved = gp - prev_pos
		moved.y = 0.0
		if moved.length() > 0.6:
			moved = Vector3.ZERO
	prev_pos = gp
	has_prev = true
	var v := moved.length() / maxf(delta, 1e-4)
	speed_s = lerpf(speed_s, v, 1.0 - exp(-delta * 14.0))
	var walk: Dictionary = clips["walk"]
	var run: Dictionary = clips["run"]
	match anim:
		"move":
			var k0 := run_k
			run_k = move_toward(run_k, smoothstep(RUN_FROM, RUN_TO, speed_s), delta * 5.0)
			var stride := lerpf(float(walk["stride"]), float(run["stride"]), run_k) * SCALE
			var still := move_speed < 0.05 and speed_s < 0.12
			if still:
				# finish the step towards feet-together (passing) and settle into idle
				stopping = true
			var adv := moved.length() / stride
			if not stopping and move_w > 0.5:
				adv = _stance_advance(adv, k0, moved.dot(-global_basis.z) / SCALE)
			if stopping:
				adv = maxf(adv, delta * 0.55)
				move_w = move_toward(move_w, 0.0, delta * 4.0)
				if move_w <= 0.0:
					_to_idle()
			else:
				move_w = move_toward(move_w, 1.0, delta * 6.0)
			var old := phase
			phase = fposmod(phase + adv, 1.0)
			if move_w > 0.5 and not stopping:
				if old > phase:
					footstep.emit(0, run_k > 0.5)
				elif old < 0.5 and phase >= 0.5:
					footstep.emit(1, run_k > 0.5)
			if not still:
				stopping = false
		"charge":
			_play(_throw_clip(), power * float(clips[_throw_clip()]["t_charge"]), 0.0)
			expr = "grit" if power > 0.35 else "smile"
			move_w = move_toward(move_w, 0.0, delta * 6.0)
		"throw":
			var c := _throw_clip()
			var tc := float(clips[c]["t_charge"])
			var L := float(clips[c]["length"])
			_play(c, minf(tc + anim_t, L), 0.08)
			expr = "grit" if anim_t < 0.3 else "smile"
			if not did_release and anim_t >= T_RELEASE:
				did_release = true
				show_stone(false)
				released.emit()
			if tc + anim_t >= L:
				_to_idle()
				act_w = 0.0
		"react":
			var c2 := "cheer" if react_kind == "cheer" else "oops"
			var L2 := float(clips[c2]["length"])
			_play(c2, minf(anim_t, L2), 0.25)
			expr = ("laugh" if react_kind == "cheer" else "oops") if anim_t > 0.15 and anim_t < L2 - 0.3 else "smile"
			if anim_t >= L2:
				_to_idle()
				act_w = 0.0
		"idle":
			move_w = move_toward(move_w, 0.0, delta * 5.0)
			if not stone.visible and act_w < 0.5:
				show_stone(true)
	if anim != "move" and anim != "idle":
		run_k = move_toward(run_k, 0.0, delta * 3.0)
	if anim != "activity":
		t_idle = fposmod(t_idle + delta, 4.0)
	act_w = move_toward(act_w, act_target, delta * act_rate)
	ab_w = move_toward(ab_w, float(cur_slot), delta * ab_rate)
	if anim == "move" and run_k > 0.6:
		expr = "laugh"
	elif anim == "move" or anim == "idle":
		expr = "smile"
	_apply_mixer()
	_plant_turn(delta)
	_foot_lock(delta)
	_update_props()
	_update_face(delta)

func _apply_mixer() -> void:
	var walk: Dictionary = clips["walk"]
	var run: Dictionary = clips["run"]
	tree.set("parameters/idle_s/seek_request", t_idle)
	tree.set("parameters/walk_s/seek_request", phase * float(walk["length"]))
	tree.set("parameters/run_s/seek_request", phase * float(run["length"]))
	tree.set("parameters/a_s/seek_request", slot_t[0])
	tree.set("parameters/b_s/seek_request", slot_t[1])
	tree.set("parameters/wr/blend_amount", run_k)
	tree.set("parameters/move/blend_amount", smoothstep(0.0, 1.0, move_w))
	tree.set("parameters/ab/blend_amount", ab_w)
	tree.set("parameters/act/blend_amount", act_w)
	tree.advance(0.0)
	if absf(turn_lean) > 0.001:
		# lean the upper body into the turn (legs untouched, so the planted feet stay put)
		var bi := skel.find_bone("spine_01")
		var par := skel.get_bone_global_pose(skel.get_bone_parent(bi)).basis
		var axis := (par.inverse() * Vector3(0, 0, 1)).normalized()
		skel.set_bone_pose_rotation(bi, Quaternion(axis, turn_lean) * skel.get_bone_pose_rotation(bi))

## planted contact (skeleton space, lowest of heel / toe pad) of one foot, or null when it is lifted
func _contact(i: int) -> Variant:
	var c: Array = contacts[i]
	var heel: Vector3 = skel.get_bone_global_pose(c[0]) * (c[1] as Vector3)
	var toe: Vector3 = skel.get_bone_global_pose(c[2]) * (c[3] as Vector3)
	var g := float(meta["ground"])
	if heel.y < g + 0.006 and toe.y < g + 0.006:
		return (heel + toe) * 0.5
	if heel.y < g + 0.006:
		return heel
	if toe.y < g + 0.006:
		return toe
	return null

func _plant_turn(delta: float) -> void:
	var yaw := global_rotation.y
	var dyaw := wrapf(yaw - plant_prev_yaw, -PI, PI)
	plant_prev_yaw = yaw
	if absf(dyaw) > 1.5:
		dyaw = 0.0
	var moving := anim == "move" and move_w > 0.5
	var lean_to := 0.0
	if moving and delta > 0.0:
		lean_to = -clampf(0.5 * speed_s * (dyaw / delta) / 9.8, -0.1, 0.1) * move_w
	turn_lean = lerpf(turn_lean, lean_to, 1.0 - exp(-delta * 5.0))
	var down: Array[Variant] = [_contact(0), _contact(1)]
	var n := int(down[0] != null) + int(down[1] != null)
	# a turn happens on one foot: with both feet down the body keeps its heading (the lag is caught up in
	# single support / flight), and in single support it pivots about the stance foot (both feet down: about
	# the middle of them). A flick of the stick turns the node at up to ~10 rad/s; the body follows at TURN_MAX
	var lag0 := plant_lag
	if moving and n == 2:
		plant_lag -= dyaw
	else:
		plant_lag *= exp(-delta * (12.0 if moving else 8.0))
	var lim := TURN_MAX * delta
	plant_lag = lag0 + clampf(dyaw + plant_lag - lag0, -lim, lim) - dyaw
	plant_lag = clampf(plant_lag, -0.35, 0.35)
	var turn := dyaw + plant_lag - lag0
	if absf(turn) > 0.0 and moving:
		var pa: Variant = null
		if n == 2 and prev_at[0] != null and prev_at[1] != null:
			pa = ((prev_at[0] as Vector3) + (prev_at[1] as Vector3)) * 0.5
		for i in 2:
			if down[i] != null and down[1 - i] == null and prev_at[i] != null:
				pa = prev_at[i]
		if pa != null:
			var o := model.global_position
			o.y = (pa as Vector3).y
			plant_off += (pa - o) - (pa - o).rotated(Vector3.UP, turn)
	plant_off = plant_off.lerp(Vector3.ZERO, 1.0 - exp(-delta * (2.0 if moving else 6.0)))
	plant_off.y = 0.0
	plant_off = plant_off.limit_length(0.25)
	model.rotation.y = PI + plant_lag
	model.position = model_base + global_basis.inverse() * plant_off
	for i in 2:
		var c: Variant = _contact(i)
		prev_at[i] = skel.global_transform * (c as Vector3) if c != null else null

## walk and run share one phase, but their stances do not line up (a walk foot is still down when the run
## one has long pushed off), so while run_k moves the blended stance foot would be dragged along. Per clip,
## sampled at load: per foot [heel z, heel y, toe z, toe y] by phase (skeleton space).
const GAIT_N := 64
var gait_tab := {}

func _build_gait_tables() -> void:
	var keep := [phase, run_k, move_w, act_w]
	for c in ["walk", "run"]:
		var rows: Array = []
		for k in GAIT_N:
			phase = float(k) / GAIT_N
			run_k = 1.0 if c == "run" else 0.0
			move_w = 1.0
			act_w = 0.0
			_apply_mixer()
			var row: Array = []
			for i in 2:
				var ct: Array = contacts[i]
				var h: Vector3 = skel.get_bone_global_pose(ct[0]) * (ct[1] as Vector3)
				var to: Vector3 = skel.get_bone_global_pose(ct[2]) * (ct[3] as Vector3)
				row.append_array([h.z, h.y, to.z, to.y])
			rows.append(row)
		gait_tab[c] = rows
	phase = keep[0]; run_k = keep[1]; move_w = keep[2]; act_w = keep[3]

## blended [heel z, heel y, toe z, toe y] of foot i at phase p and walk / run mix k
func _gait_at(i: int, p: float, k: float) -> Array:
	var f := fposmod(p, 1.0) * GAIT_N
	var a := int(f) % GAIT_N
	var b := (a + 1) % GAIT_N
	var u := f - floorf(f)
	var w: Array = gait_tab["walk"]
	var r: Array = gait_tab["run"]
	var out: Array = []
	for j in 4:
		var vw := lerpf(float(w[a][i * 4 + j]), float(w[b][i * 4 + j]), u)
		var vr := lerpf(float(r[a][i * 4 + j]), float(r[b][i * 4 + j]), u)
		out.append(lerpf(vw, vr, k))
	return out

## z of foot i's planted point at (p, k): heel, toe pad or between them as in _foot_lock; null when lifted.
## `kind` (0 heel, 1 toe, 2 both) pins the point when given.
func _plant_z(i: int, p: float, k: float, kind := -1) -> Variant:
	var s := _gait_at(i, p, k)
	var th := float(meta["ground"]) + 0.008
	if kind < 0:
		var hd := float(s[1]) < th
		var td := float(s[3]) < th
		if not hd and not td:
			return null
		kind = 2 if hd and td else (0 if hd else 1)
	return [float(s[0]) if kind == 0 else (float(s[2]) if kind == 1 else (float(s[0]) + float(s[2])) * 0.5), kind]

## phase advance that moves the blended stance foot back by exactly the distance the body went forward
## (skeleton units), so a changing walk / run mix does not drag it; the plain stride rate otherwise
func _stance_advance(adv: float, k0: float, fwd: float) -> float:
	if gait_tab.is_empty() or absf(run_k - k0) < 1e-5:
		return adv
	var best := -1
	var lo := 1e9
	for i in 2:
		var s := _gait_at(i, phase, k0)
		var hmin := minf(float(s[1]), float(s[3]))
		if hmin < lo:
			lo = hmin
			best = i
	var p0: Variant = _plant_z(best, phase, k0)
	if p0 == null:
		return adv
	var target := float(p0[0]) - fwd
	var kind: int = p0[1]
	var span := maxf(adv * 4.0, 0.03)
	var prev_f := float(_plant_z(best, phase, run_k, kind)[0]) - target
	if prev_f <= 0.0:
		return 0.0
	var n := 16
	for j in range(1, n + 1):
		var q := phase + span * j / n
		var f := float(_plant_z(best, q, run_k, kind)[0]) - target
		if f <= 0.0:
			return span * (float(j - 1) + prev_f / (prev_f - f)) / n
		prev_f = f
	return span

func _foot_lock(delta: float) -> void:
	var S := skel.global_transform
	var Si := S.affine_inverse()
	var g := float(meta["ground"])
	var on := lock_enabled and (anim == "move" or anim == "idle") and act_w < 0.05
	var jumped := global_position.distance_to(lock_pos) > 0.6
	lock_pos = global_position
	for i in 2:
		var lb: Array = legs[i]
		var ct: Array = contacts[i]
		if jumped:
			lock_c[i] = Vector3.ZERO; lock_yaw[i] = 0.0; lock_on[i] = false; lock_prev[i] = null
			step_t[i] = -1.0; pivot_w[i] = 0.0
		var F := skel.get_bone_global_pose(lb[2])
		var B := skel.get_bone_global_pose(lb[3])
		var A := F.origin
		var heel := F * (ct[1] as Vector3)
		var toe := B * (ct[3] as Vector3)
		var th := g + (0.015 if lock_on[i] else 0.008)
		var hd := heel.y < th
		var td := toe.y < th
		var planted := on and (hd or td) and lock_prev[i] != null and step_t[i] < 0.0
		if planted:
			var pv: Array = lock_prev[i]
			# heading: while the foot is flat, undo whatever the animation / body turn did to its yaw since
			# last frame; on the heel or the ball alone it pivots with the body about that point. A sharp turn
			# (past PIVOT_YAW of twist) rolls a flat foot up onto the ball and pivots there
			if hd and td:
				var fw := S.basis * (Basis(Vector3.UP, lock_yaw[i]) * (B.origin - A))
				lock_yaw[i] -= wrapf(atan2(fw.x, fw.z) - float(pv[2]), -PI, PI)
				if absf(lock_yaw[i]) > PIVOT_YAW:
					lock_yaw[i] = clampf(lock_yaw[i], -PIVOT_YAW, PIVOT_YAW)
					pivot_w[i] = 1.0
			var on_ball := td and (pivot_w[i] > 0.0 or not hd)
			# position: the planted point (heel, toe pad or both) back where it was
			var pa: Vector3 = toe if on_ball else (heel if not td else (heel + toe) * 0.5)
			var was: Vector3 = pv[1] if on_ball else (pv[0] if not td else ((pv[0] as Vector3) + (pv[1] as Vector3)) * 0.5)
			var now := Basis(Vector3.UP, lock_yaw[i]) * (pa - A) + A + lock_c[i]
			var d := Si.basis * (was - S * now)
			d.y = 0.0
			lock_c[i] += d
			lock_on[i] = true
			if lock_c[i].length() > STEP_AT:
				# the body has got too far from the planted foot (a flick of the stick): a quick step
				step_t[i] = 0.0
				step_from[i] = [lock_c[i], lock_yaw[i]]
				steps_taken += 1
				planted = false
		var lift := 0.0
		if step_t[i] >= 0.0:
			lock_on[i] = false
			step_t[i] += delta
			var u := minf(step_t[i] / STEP_DUR, 1.0)
			var w := 1.0 - smoothstep(0.0, 1.0, u)
			lock_c[i] = (step_from[i][0] as Vector3) * w
			lock_yaw[i] = float(step_from[i][1]) * w
			lift = STEP_LIFT * sin(PI * u)
			if u >= 1.0:
				step_t[i] = -1.0
		elif not planted:
			lock_on[i] = false
			var k := exp(-delta * 10.0)
			lock_c[i] *= k
			lock_yaw[i] *= k
		var R := Basis(Vector3.UP, lock_yaw[i])
		var heel_c := R * (heel - A) + A + lock_c[i]
		var toe_c := R * (toe - A) + A + lock_c[i]
		var ankle := A + lock_c[i]
		var fb := R * F.basis
		if lift > 0.0:
			heel_c.y += lift; toe_c.y += lift; ankle.y += lift
		if pivot_w[i] > 0.0:
			var fwd := toe_c - heel_c
			fwd.y = 0.0
			var Rp := Basis(Vector3.UP.cross(fwd).normalized(), PIVOT_LIFT * smoothstep(0.0, 1.0, pivot_w[i]))
			ankle = toe_c + Rp * (ankle - toe_c)
			heel_c = toe_c + Rp * (heel_c - toe_c)
			fb = Rp * fb
			pivot_w[i] = move_toward(pivot_w[i], 0.0, delta * 4.0)
		if lock_c[i].length_squared() > 1e-10 or absf(lock_yaw[i]) > 1e-5 or pivot_w[i] > 0.0 or lift > 0.0:
			_leg_ik(lb, ankle, fb, R)
		var hw := S * heel_c
		var tw := S * toe_c
		var fw2 := S.basis * (R * (B.origin - A))
		lock_prev[i] = [hw, tw, atan2(fw2.x, fw2.z)]

## two-bone IK (skeleton space): ankle to `ankle`, foot to `foot_b`; the knee stays in the animated leg's
## plane, turned with the foot by `twist`
func _leg_ik(lb: Array, ankle: Vector3, foot_b: Basis, twist: Basis) -> void:
	var Tg := skel.get_bone_global_pose(lb[0])
	var Cg := skel.get_bone_global_pose(lb[1])
	var Fg := skel.get_bone_global_pose(lb[2])
	var H := Tg.origin
	var K := Cg.origin
	var A := Fg.origin
	var l1 := H.distance_to(K)
	var l2 := K.distance_to(A)
	var to := ankle - H
	var dist := clampf(to.length(), absf(l1 - l2) + 1e-4, (l1 + l2) * 0.9999)
	var u := to.normalized()
	var la := (A - H).normalized()
	var pole := twist * ((K - H) - la * (K - H).dot(la))
	if pole.length_squared() < 1e-10:
		pole = twist * (Tg.basis * Vector3(0, 0, 1))
	var v := (pole - u * pole.dot(u)).normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var K2 := H + u * a + v * sqrt(maxf(l1 * l1 - a * a, 0.0))
	var A2 := H + u * dist
	var n_old := (K - H).cross(A - K)
	var n_new := (K2 - H).cross(A2 - K2)
	if n_old.length_squared() < 1e-12 or n_new.length_squared() < 1e-12:
		n_old = Tg.basis.x
		n_new = twist * Tg.basis.x
	var q1 := _frame_rot(K - H, n_old, K2 - H, n_new)
	var q2 := _frame_rot(A - K, n_old, A2 - K2, n_new)
	var Tb := q1 * Tg.basis
	var Cb := q2 * Cg.basis
	var Pg := skel.get_bone_global_pose(skel.get_bone_parent(lb[0])).basis
	skel.set_bone_pose_rotation(lb[0], (Pg.inverse() * Tb).get_rotation_quaternion())
	skel.set_bone_pose_rotation(lb[1], (Tb.inverse() * Cb).get_rotation_quaternion())
	skel.set_bone_pose_rotation(lb[2], (Cb.inverse() * foot_b).get_rotation_quaternion())

## rotation taking direction d0 (with n0 as the second axis) onto d1 / n1
static func _frame_rot(d0: Vector3, n0: Vector3, d1: Vector3, n1: Vector3) -> Basis:
	var e1 := d0.normalized()
	var e2 := (n0 - e1 * n0.dot(e1)).normalized()
	var f1 := d1.normalized()
	var f2 := (n1 - f1 * n1.dot(f1)).normalized()
	var m0 := Basis(e1, e2, e1.cross(e2))
	var m1 := Basis(f1, f2, f1.cross(f2))
	return m1 * m0.transposed()

## mid-stride when the stick is let go: main.gd keeps creeping forward until the passing pose (one foot
## under the hips, the other in the air), so the cross-fade to idle never drags a planted foot
func settling() -> bool:
	if anim != "move" or move_w < 0.5:
		return false
	var p := fposmod(phase, 0.5)
	var q := fposmod(settle_ph, 0.5)
	settle_ph = phase
	if p >= 0.27 and p <= 0.36:
		return false
	# at a low frame rate one tick can step right over the window
	return not (q < 0.27 and p > 0.36 and p - q < 0.25)

func _update_props() -> void:
	var want: Node3D = hat_head_parent
	var xf := hat_head_xf
	match hat_mode:
		"chest":
			# lying on the chest, crown up towards the sky
			want = chest_att
			xf = _skel_to_bone(chest_att.bone_name, _hat_at(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.0, 0.16)))
		"face":
			# tipped down over his face against the sun, brim resting on the chin and forehead
			want = parts["head"]
			var hb := skel.find_bone("head")
			var hp := skel.get_bone_global_rest(hb).origin
			xf = _skel_to_bone("head", _hat_at(Basis(Vector3.RIGHT, PI * 0.5 - 0.05), hp + Vector3(0, 0.0, 0.125)))
		"ground":
			# on the towel next to his right shoulder (the lying body frame is upright, back = -Z)
			want = model
			xf = _hat_at(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, 0.4), Vector3(-0.45, 1.22, -0.12))
	if hat.get_parent() != want:
		hat.reparent(want, false)
	hat.transform = xf
	var pel := (parts["pelvis"] as Node3D).global_position
	var lp := to_local(pel)
	blob.position = Vector3(lp.x * 0.6, 0.012, lp.z * 0.6)

## hat transform (skeleton rest space) putting the centre of its band rim at `base` with orientation `b`
## (the hat mesh keeps its rest-pose vertex positions, so its origin is the model origin)
func _hat_at(b: Basis, base: Vector3) -> Transform3D:
	var bb := (hat as MeshInstance3D).get_aabb()
	var c := bb.get_center()
	c.y = bb.position.y + 0.03
	return Transform3D(b, base - b * c)

## a transform given in skeleton rest space, expressed in a bone's frame
func _skel_to_bone(bone: String, xf: Transform3D) -> Transform3D:
	var bi := skel.find_bone(bone)
	return skel.get_bone_global_rest(bi).affine_inverse() * xf

func _update_face(delta: float) -> void:
	blink_timer -= delta
	var open := 1.0
	if blink_timer < 0.12:
		open = 0.0
		if blink_timer < 0.0:
			blink_timer = rng.randf_range(2.0, 4.5)
	var mouth := 0
	match expr:
		"laugh": mouth = 1; open = 0.0
		"oops": mouth = 2
		"grit": mouth = 3
		"sleep": mouth = 4; open = 0.0
		"relax": open = 0.0
	face_mat.set_shader_parameter("eye_open", open)
	face_mat.set_shader_parameter("mouth", mouth)

# ------------------------------------------------------------------ dev helpers

## Freeze a named pose (screenshots / tests). Returns the pelvis in boy space.
func debug_pose(kind: String, p := 1.0, tt := 0.3) -> Vector3:
	frozen = true
	stance = "crouch" if kind.ends_with("_c") else "stand"
	act_w = 1.0
	ab_w = 0.0
	cur_slot = 0
	hat_mode = "head"
	glasses.visible = false
	var e := "smile"
	var pel := Vector3.ZERO
	match kind:
		"charge", "charge_c":
			_set_slot(0, _throw_clip(), p * float(clips[_throw_clip()]["t_charge"])); e = "grit"
		"release", "release_c":
			_set_slot(0, _throw_clip(), float(clips[_throw_clip()]["t_release"])); e = "grit"
		"follow", "follow_c":
			_set_slot(0, _throw_clip(), 0.82 + p * 0.3)
		"cheer", "oops":
			_set_slot(0, kind, tt); e = "laugh" if kind == "cheer" else "oops"
		"walk", "run":
			act_w = 0.0; move_w = 1.0; run_k = 1.0 if kind == "run" else 0.0; phase = tt
		"sleep", "sun":
			var c := "hammock_sleep" if kind == "sleep" else "sun_rest"
			_set_slot(0, c, tt)
			hat_mode = "chest" if kind == "sleep" else "ground"
			glasses.visible = kind == "sun"
			e = "sleep" if kind == "sleep" else "relax"
		"sit_edge", "sit_ground":
			_set_slot(0, "hammock_sit" if kind == "sit_edge" else "sun_sit", 1.0)
		_:
			act_w = 0.0; move_w = 0.0; t_idle = tt
	expr = e
	_apply_mixer()
	_update_props()
	blink_timer = 9.0
	_update_face(0.0)
	return pel
