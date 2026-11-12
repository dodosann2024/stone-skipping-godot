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
## a walking / running foot has just come down flat (heel and ball on the ground): where its print goes
signal foot_flat(side: int)

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
var head_mi: MeshInstance3D      # the face region, split off with the expression morphs
var morph_idx := {}              # morph name -> blend shape index
var morph := {}                  # morph name -> current weight (eased toward the expression's)
var hair_mat: ShaderMaterial
var hair_mi: MeshInstance3D
var hat: Node3D
var glasses: Node3D
var stone: Node3D
var blob: MeshInstance3D
# the hat is a rigid prop on the head bone. It has two seats there (head bone -> hat): on his head, and
# tipped down over his face for lying on his back (a brim that wide cannot stay on a head lying flat: its
# back edge would be ~10 cm into the bed). Only his hand moves it from one to the other.
var hat_head_xf: Transform3D
var hat_face_xf: Transform3D
var hat_head_parent: BoneAttachment3D
var head_bone := -1
var hat_s := 0.0      # 0 on his head .. 1 over his face
var hat_hold := 0.0   # 0 .. 1: the hand on the front of the brim (arm IK weight)
var hat_side := "r"
var hat_band_c := Vector3.ZERO   # centre of the band rim (hat local)
var hat_grip := {}    # side -> [wrist, finger direction, palm normal] in hat local space
var hand_loc := {}    # side -> [finger direction, palm normal] in the hand bone's frame
var arm_bones := {}   # side -> [clavicle, upperarm, lowerarm, hand, deltoid]
# lie_k: hand reaches the brim [0] -> [1], moves the hat over his face [1] -> [2], lets go [3] -> [4];
# getting up runs the same backwards
const HAT_LIE := {"": [0.0, 0.16, 0.5, 0.72, 0.92], "seatlie": [0.3, 0.55, 0.9, 0.92, 0.99]}
const HAT_LIFT := 0.07   # the hat's arc away from his face (skeleton m)
const HAT_TIP := {"sleep": -0.6, "seatlie": -0.55}   # rad, left side of the brim up over his face
# hat-local shift over his face: getting up from the towel his left thumb sweeps past the crown
const HAT_SHIFT := {"sun": Vector3(-0.032, 0.0, 0.0)}
var hat_tip := 0.0
var hat_shift := Vector3.ZERO

var t := 0.0
var t_idle := 0.0
var phase := 0.0
var move_w := 0.0
var run_k := 0.0
var walk_k := 1.0    # stroll 0 -> walk 1 (under run_k): shorter, slower steps at low speed
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
var blink_t := -1.0              # time into the current blink (< 0: none)
var blink_twice := false
var expr := "smile"
var rng := RandomNumberGenerator.new()
var frozen := false
# hair secondary motion: tip offset (world) on a damped spring driven by the head's acceleration + wind
var hair_off := Vector3.ZERO
var hair_vel := Vector3.ZERO
var hair_prev := Vector3.ZERO
var hair_pv := Vector3.ZERO
var hair_t := 0.0
var wind := 1.0
# clothes: loose hems (shorts legs, vest front edges) trail the pelvis the same way
var cloth_mats: Array[ShaderMaterial] = []
var cloth_off := Vector3.ZERO
var cloth_vel := Vector3.ZERO
var cloth_prev := Vector3.ZERO
var cloth_pv := Vector3.ZERO
# a slower, softer copy of that spring (parts of a hem lag behind others instead of the whole hem moving
# as one piece), and one spring per shorts leg on its knee (the leg openings swing with each thigh)
var cloth_off2 := Vector3.ZERO
var cloth_vel2 := Vector3.ZERO
var leg_prev: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var leg_pv: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var leg_off: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var leg_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
# turning pivots about the planted foot: the root yaws about its own origin, which would drag a planted
# foot sideways, so the model is shifted (world-space offset, bled back to zero) to keep that contact put
var model_base := Vector3.ZERO
var plant_off := Vector3.ZERO
var plant_prev_yaw := 0.0
var plant_lag := 0.0
var prev_at: Array[Variant] = [null, null]
var turn_lean := 0.0
var turn_w := 0.0              # rad/s the body has been turning (smoothed)
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
var flat_sent := [false, false]
var swing_t := [-1.0, -1.0]
var swing_from := [[Vector3.ZERO, 0.0], [Vector3.ZERO, 0.0]]
var phase_rate := 0.0
var was_down := [false, false]
var pivot_w: Array[float] = [0.0, 0.0]
var heel_up: Array[float] = [0.0, 0.0]   # rad: a trailing foot past its reach rolls up onto the ball
var step_t: Array[float] = [-1.0, -1.0]
var steps_taken := 0
var spot_steps := 0
var step_from: Array = [[Vector3.ZERO, 0.0], [Vector3.ZERO, 0.0]]
const PIVOT_YAW := 0.45
const TURN_MAX := 12.0
const STEP_FAR := 0.22       # skeleton units (~19 cm)
const SLIP := 0.0025
const STEP_REACH := 0.97     # of the leg's length, and clearly more than the animation's
const STEP_DUR := 0.16
const STEP_LIFT := 0.06
const PIVOT_LIFT := 0.3
const HEEL_UP := 0.6
const HEEL_FROM := 0.965      # leg stretch (of its length) at which the heel starts to come up
const TURN_AIM := 0.6         # rad: a foot lands turned into the turn by at most this
# turning on the spot (the mover sets `pivoting` and `turn_ahead`): the head leads, then the feet take turns
# stepping round, inner foot first, and each step carries the body round with it (a half turn: open, turn,
# close); weight goes onto the standing foot
const SPOT_YAW := 0.2         # a foot left this twisted / this far off its spot closes up after the turn
const SPOT_C := 0.05
const SPOT_LEAD := 1.6        # how far round (rad) one step turns the body, at most
const SPOT_END := 0.2
const SPOT_DUR := 0.3
const SPOT_LIFT := 0.05
const SPOT_GAP := 0.06        # s both feet are down between two steps round
const SPOT_WAIT := 0.08       # s the head leads before the first step
const SPIN_CENTER := 0.7      # the body turns about this far from the standing foot's ball to its own middle
const SPOT_RATE := 3.4        # rad/s, the fastest turn on the spot
const STEER_GRIP := 4.5       # m/s^2 a kid can lean into a corner
const STEER_TOP := 6.0        # rad/s, the fastest turn while moving
var pivoting := false
var turn_ahead := 0.0         # rad (+ = left) the heading still has to turn, from the mover
var aim_twist := 0.0          # rad (+ = left) the chest turns ahead of the hips while aiming a throw
const TWIST_BONES := ["spine_01", "spine_02", "spine_03"]
const TWIST_SHARE := [0.3, 0.35, 0.35]
var lead_y := [0.0, 0.0, 0.0, 0.0]   # spine_02, spine_03, neck_01, head yaw: the head goes first
var step_to: Array = [[Vector3.ZERO, 0.0], [Vector3.ZERO, 0.0]]
var step_dur: Array[float] = [STEP_DUR, STEP_DUR]
var step_lift: Array[float] = [STEP_LIFT, STEP_LIFT]
var last_step_foot := -1
var step_world: Array = [null, null]   # spot steps: [from pos, from heading, to pos, to heading] in the world
var idle_still := 0.0
var spot_gap := 0.0
var spin := false             # turning on the spot (or finishing one): the steps turn the body
var spin_h: Array = [null, null]   # per stepping foot: [body heading at its start, at its end] (world)
var spin_wait := 0.0
var spin_t := 0.0
var was_pivoting := false
var last_dt := 0.0
const SPIN_LAG := 1.4
var lead_dt := 0.0
var hip_shift := Vector3.ZERO   # skeleton space; the feet do not move with it

## the turn-on-the-spot rule shared by main.gd and the gait probe: [new heading, new turn rate]
static func spot_turn(face: float, want: float, rate: float, delta: float) -> Array:
	var need := wrapf(want - face, -PI, PI)
	var top := minf(SPOT_RATE, 1.2 + absf(need) * 2.6)
	rate = move_toward(rate, top, delta * 14.0)
	var stp := minf(absf(need), rate * delta)
	return [face + signf(need) * stp, rate]

## when a change of heading `need` at `speed` (m/s) is a turn on the spot instead (main.gd and the probe)
static func wants_spot_turn(need: float, speed: float) -> bool:
	return (absf(need) > 1.1 and speed < 0.4) or (absf(need) > 2.0 and speed < 0.9)

## the moving-turn rule shared by main.gd and the gait probe: the heading eases towards `want`, but no faster
## than his feet can corner at `speed` (STEER_GRIP of sideways push), and a sharp change slows him down first.
## [new heading, factor on the wanted speed]
static func move_turn(face: float, want: float, speed: float, delta: float) -> Array:
	var need := wrapf(want - face, -PI, PI)
	var top := minf(STEER_TOP, STEER_GRIP / maxf(speed, 0.3))
	var stp := minf(absf(need), minf(top, absf(need) * 9.0) * delta)
	return [face + signf(need) * stp, 1.0 - 0.72 * smoothstep(0.5, 1.6, absf(need))]

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

func _cloth_mat(col: Color, p: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/cloth.gdshader")
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("fabric_tex", preload("res://textures/fabric.png"))
	for k: String in p:
		m.set_shader_parameter(k, p[k])
	return m

func _setup_materials() -> void:
	# albedo per Blender material name; kinds: 0 skin, 1 cloth, 2 hair, 3 straw, 4 props
	var look := {
		"skin": [Color(1.0, 0.82, 0.64), 0], "mouth": [Color(0.3, 0.1, 0.09), 5], "tank": [Color(0.95, 0.94, 0.90), 1],
		"vest": [Color(0.80, 0.27, 0.22), 1], "shorts": [Color(0.96, 0.80, 0.36), 1],
		"hair": [Color(0.30, 0.20, 0.14), 2], "sandal": [Color(0.36, 0.60, 0.64), 1],
		"strap": [Color(0.95, 0.93, 0.88), 1], "hat": [Color(0.92, 0.80, 0.55), 3],
		"band": [Color(0.78, 0.25, 0.20), 1], "lens": [Color(0.08, 0.09, 0.11), 4],
		"stone": [Color(0.55, 0.56, 0.58), 4], "cord": [Color(0.93, 0.91, 0.85), 1],
	}
	# fabric 0 jersey, 1 linen, 2 twill (textures/fabric.png channels)
	var fabric := {
		"tank": {"fabric": 0, "thread": Color(0.97, 0.96, 0.93), "hem_stitch": 0.006, "fade": 0.0,
			"wear": 0.15, "sheen": 0.35, "translucency": 0.16},
		"vest": {"fabric": 1, "thread": Color(0.88, 0.45, 0.37), "binding": Color(0.60, 0.17, 0.14),
			"binding_w": 0.0055, "hem_stitch": 0.0075, "fade": 0.3, "wear": 0.3, "sheen": 0.25, "wrinkle": 0.003,
			"pit_depth": 0.009},
		"shorts": {"fabric": 2, "thread": Color(0.99, 0.89, 0.58), "hem_stitch": 0.011, "fade": 0.25,
			"wear": 0.3, "sheen": 0.2, "legs": 1.0},
	}
	var made := {}     # one material per name: BoyMesh and BoyHead share the skin
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi.mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var n := src.resource_name if src else ""
			if made.has(n):
				mi.set_surface_override_material(i, made[n])
				continue
			if n == "eye":
				var em := ShaderMaterial.new()
				em.shader = preload("res://shaders/eye.gdshader")
				made[n] = em
				mi.set_surface_override_material(i, em)
				continue
			if not look.has(n):
				continue
			var m := _mat(look[n][0], look[n][1])
			made[n] = m
			if fabric.has(n):
				m = _cloth_mat(look[n][0], fabric[n])
				cloth_mats.append(m)
			elif n == "hair":
				m = ShaderMaterial.new()
				m.shader = preload("res://shaders/hair.gdshader")
				hair_mat = m
				hair_mi = mi
				# the locks shadowing each other read as roof tiles; the hat's shadow does the shading
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.set_surface_override_material(i, m)
			if n == "skin":
				face_mat = m
				m.set_shader_parameter("face_tex", preload("res://textures/face_detail.png"))
				var r: Array = meta.get("face_rect", [-0.075, -0.085, 0.15, 0.18])
				m.set_shader_parameter("face_rect", Vector4(r[0], r[1], r[2], r[3]))
		if mi.name in ["Glasses", "Stone", "Eyes"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.name == "BoyHead":
			head_mi = mi
			for k in mi.mesh.get_blend_shape_count():
				morph_idx[String(mi.mesh.get_blend_shape_name(k))] = k
				morph[String(mi.mesh.get_blend_shape_name(k))] = 0.0

func _setup_parts() -> void:
	for att: BoneAttachment3D in skel.find_children("*", "BoneAttachment3D", false, false):
		for c in att.get_children():
			match String(c.name):
				"Hat": hat = c
				"Glasses": glasses = c
				"Stone": stone = c
	hat_head_parent = hat.get_parent()
	hat_head_xf = hat.transform
	head_bone = skel.find_bone(hat_head_parent.bone_name)
	_setup_hat_seats()
	glasses.visible = false
	for b in ["head", "pelvis", "spine_03"]:
		var a := BoneAttachment3D.new()
		a.name = "att_" + b
		a.bone_name = b
		skel.add_child(a)
		parts[b] = a

func _anim_node(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n

func _setup_tree() -> void:
	var ap := model.find_child("AnimationPlayer") as AnimationPlayer
	bt = AnimationNodeBlendTree.new()
	var x := 0.0
	for pair in [["idle", "idle"], ["stroll", "stroll"], ["walk", "walk"], ["run", "run"], ["a", "idle"], ["b", "idle"]]:
		bt.add_node(pair[0], _anim_node(pair[1]), Vector2(0, x))
		bt.add_node(pair[0] + "_s", AnimationNodeTimeSeek.new(), Vector2(200, x))
		bt.connect_node(pair[0] + "_s", 0, pair[0])
		x += 120.0
	bt.add_node("sw", AnimationNodeBlend2.new(), Vector2(400, 0))
	bt.connect_node("sw", 0, "stroll_s")
	bt.connect_node("sw", 1, "walk_s")
	bt.add_node("wr", AnimationNodeBlend2.new(), Vector2(400, 100))
	bt.connect_node("wr", 0, "sw")
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
	_hat_for(kind, lie_k)
	glasses.visible = kind == "sun" and lie_k > 0.5
	blob.visible = sit_k < 0.3 and lie_k <= 0.0
	if kind == "sleep" or kind == "seatlie":
		expr = "sleep" if lie_k > 0.7 else "smile"
	else:
		expr = "relax" if lie_k > 0.5 else "smile"
	show_stone(false)
	return _track(clip, "pelvis", u)

func end_activity() -> void:
	hat_s = 0.0
	hat_hold = 0.0
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
	_update_hair(delta)
	_update_cloth(delta)
	if frozen:
		return
	_tick(delta)

## hair tips lag behind the head (a damped spring on its acceleration), a little breeze and gravity
## pulling the fringe / sides when the head tilts; at most a few mm, so the cards never reach the skin
## or the hat brim. Under the hat crown the hair only moves while the hat is off.
func _update_hair(delta: float) -> void:
	if hair_mat == null or delta <= 0.0:
		return
	hair_t += delta
	var hb := skel.find_bone("head")
	var hx := skel.global_transform * skel.get_bone_global_pose(hb)
	var p := hx.origin
	var v := (p - hair_prev) / delta
	var acc := (v - hair_pv) / delta
	if hair_prev == Vector3.ZERO or acc.length() > 80.0:
		acc = Vector3.ZERO
	hair_prev = p
	hair_pv = v
	var rest := skel.global_transform.basis * skel.get_bone_global_rest(hb).basis
	var down_rest := (hx.basis * rest.inverse() * Vector3.DOWN).normalized()
	var gust := 0.6 + 0.4 * sin(hair_t * 0.7) * sin(hair_t * 1.9 + 1.0)
	var breeze := Vector3(0.8, 0.0, 0.45) * (0.0012 * wind * gust)
	var target := -acc * 0.0007 + breeze + (Vector3.DOWN - down_rest) * 0.0022
	target = target.limit_length(0.005)
	hair_vel += ((target - hair_off) * 160.0 - hair_vel * 14.0) * minf(delta, 0.05)
	hair_off += hair_vel * minf(delta, 0.05)
	hair_off = hair_off.limit_length(0.006)
	var inv := hair_mi.global_transform.basis.inverse()
	hair_mat.set_shader_parameter("sway", inv * hair_off)
	hair_mat.set_shader_parameter("flutter", 0.0004 * wind * gust / SCALE)
	hair_mat.set_shader_parameter("game_time", hair_t)
	hair_mat.set_shader_parameter("hat_on", (1.0 - smoothstep(0.0, 0.4, hat_s)) if hat.visible else 0.0)

## a few mm of lag on the free hems; the shorts legs flare ~2 cm off the thighs and the vest hangs
## 4 mm over the waistband, so this never reaches skin or the layer below
func _update_cloth(delta: float) -> void:
	if cloth_mats.is_empty() or delta <= 0.0:
		return
	var p := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("pelvis"))).origin
	var v := (p - cloth_prev) / delta
	var acc := (v - cloth_pv) / delta
	if cloth_prev == Vector3.ZERO or acc.length() > 80.0:
		acc = Vector3.ZERO
	cloth_prev = p
	cloth_pv = v
	var gust := 0.6 + 0.4 * sin(hair_t * 0.7) * sin(hair_t * 1.9 + 1.0)
	var target := -acc * 0.0005 + Vector3(0.8, 0.0, 0.45) * (0.0012 * wind * gust)
	target = target.limit_length(0.004)
	var dt := minf(delta, 0.05)
	cloth_vel += ((target - cloth_off) * 110.0 - cloth_vel * 11.0) * dt
	cloth_off += cloth_vel * dt
	cloth_off = cloth_off.limit_length(0.005)
	cloth_vel2 += ((target - cloth_off2) * 45.0 - cloth_vel2 * 6.0) * dt
	cloth_off2 += cloth_vel2 * dt
	cloth_off2 = cloth_off2.limit_length(0.005)
	var legs: Array[Vector3] = []
	for i in 2:
		var k := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone(["calf_l", "calf_r"][i]))).origin
		var lv := (k - leg_prev[i]) / delta
		var la := (lv - leg_pv[i]) / delta
		if leg_prev[i] == Vector3.ZERO or la.length() > 120.0:
			la = Vector3.ZERO
		leg_prev[i] = k
		leg_pv[i] = lv
		# relative to the pelvis: the hem trails its own thigh's swing (half way down to the knee)
		var lt := (-(la - acc) * 0.00022).limit_length(0.003)
		leg_vel[i] += ((lt - leg_off[i]) * 90.0 - leg_vel[i] * 8.0) * dt
		leg_off[i] += leg_vel[i] * dt
		leg_off[i] = leg_off[i].limit_length(0.004)
		legs.append(leg_off[i])
	# how far each upper arm is raised off the torso's side: the vest folds under it from ~50 to ~110 deg
	var up := skel.get_bone_global_pose(skel.find_bone("spine_03")).basis.y.normalized()
	var pit := Vector2.ZERO
	for i in 2:
		var arm := skel.get_bone_global_pose(skel.find_bone(["upperarm_l", "upperarm_r"][i])).basis.y.normalized()
		pit[i] = smoothstep(deg_to_rad(50.0), deg_to_rad(110.0), arm.angle_to(-up))
	var inv := hair_mi.global_transform.basis.inverse()
	for m in cloth_mats:
		m.set_shader_parameter("pit", pit)
		m.set_shader_parameter("sway", inv * cloth_off)
		m.set_shader_parameter("sway2", inv * cloth_off2)
		m.set_shader_parameter("sway_l", inv * legs[0])
		m.set_shader_parameter("sway_r", inv * legs[1])
		m.set_shader_parameter("flutter", 0.0003 * wind * gust / SCALE)
		m.set_shader_parameter("game_time", hair_t)

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
			var k0 := _mix()
			run_k = move_toward(run_k, smoothstep(RUN_FROM, RUN_TO, speed_s), delta * 5.0)
			var still := move_speed < 0.05 and speed_s < 0.12
			if still:
				# finish the step towards feet-together (passing) and settle into idle
				stopping = true
			if not stopping:
				# (held while stopping: the stance foot is not re-solved then, a changing mix would drag it)
				var vs := float(clips["stroll"]["speed"]) * SCALE
				walk_k = move_toward(walk_k, smoothstep(vs, float(walk["speed"]) * SCALE, speed_s), delta * 2.0)
			var stride := _stride()
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
			phase_rate = adv / maxf(delta, 1e-4)
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
	if anim != "move":
		walk_k = move_toward(walk_k, 0.0, delta * 3.0)
	if anim != "activity":
		t_idle = fposmod(t_idle + delta, 4.0)
	act_w = move_toward(act_w, act_target, delta * act_rate)
	ab_w = move_toward(ab_w, float(cur_slot), delta * ab_rate)
	if anim == "move" and run_k > 0.6:
		expr = "run"
	elif anim == "move" or anim == "idle":
		expr = "smile"
	lead_dt = delta
	_apply_mixer()
	lead_dt = 0.0
	_plant_turn(delta)
	_foot_lock(delta)
	_hat_hands()
	_update_props()
	_update_face(delta)

func _apply_mixer() -> void:
	var walk: Dictionary = clips["walk"]
	var run: Dictionary = clips["run"]
	tree.set("parameters/idle_s/seek_request", t_idle)
	tree.set("parameters/stroll_s/seek_request", phase * float(clips["stroll"]["length"]))
	tree.set("parameters/walk_s/seek_request", phase * float(walk["length"]))
	tree.set("parameters/run_s/seek_request", phase * float(run["length"]))
	tree.set("parameters/a_s/seek_request", slot_t[0])
	tree.set("parameters/b_s/seek_request", slot_t[1])
	tree.set("parameters/sw/blend_amount", walk_k)
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
	_lead_turn()
	if absf(aim_twist) > 1e-4:
		twist_spine(skel, aim_twist)
	_weight_shift()

## a turn starts at the eyes: head, then chest, then hips (the legs follow with the feet)
func _lead_turn() -> void:
	var dt := lead_dt
	var ah := clampf(turn_ahead - plant_lag, -1.8, 1.8) if (anim == "move" or anim == "idle") else 0.0
	ah *= 1.0 - act_w
	var share := [0.1, 0.17, 0.16, 0.2]
	var top := [0.16, 0.28, 0.3, 0.38]
	var rate := [5.0, 7.0, 11.0, 14.0]
	var names := ["spine_02", "spine_03", "neck_01", "head"]
	for j in 4:
		var want := clampf(ah * float(share[j]), -float(top[j]), float(top[j]))
		lead_y[j] = lerpf(lead_y[j], want, 1.0 - exp(-dt * float(rate[j])))
		if absf(lead_y[j]) < 1e-4:
			continue
		var bi := skel.find_bone(names[j])
		var par := skel.get_bone_global_pose(skel.get_bone_parent(bi)).basis
		var axis := (par.inverse() * Vector3.UP).normalized()
		skel.set_bone_pose_rotation(bi, Quaternion(axis, lead_y[j]) * skel.get_bone_pose_rotation(bi))

## turn the chest `tw` rad about the vertical over the hips (shared up the spine; legs and hips untouched)
static func twist_spine(sk: Skeleton3D, tw: float) -> void:
	for j in TWIST_BONES.size():
		var bi := sk.find_bone(TWIST_BONES[j])
		var par := sk.get_bone_global_pose(sk.get_bone_parent(bi)).basis
		var axis := (par.inverse() * Vector3.UP).normalized()
		sk.set_bone_pose_rotation(bi, Quaternion(axis, tw * float(TWIST_SHARE[j])) * sk.get_bone_pose_rotation(bi))

## while one foot is stepping round, the hips sway over the other one and dip a little
func _weight_shift() -> void:
	var off := Vector3.ZERO
	hip_shift = Vector3.ZERO
	for i in 2:
		if step_t[i] >= 0.0 and spin:
			var u := clampf(step_t[i] / step_dur[i], 0.0, 1.0)
			var sw := sin(PI * minf(u * 1.25, 1.0))
			off += Vector3(0.028 if i == 1 else -0.028, -0.012, 0.0) * sw
	if off.length_squared() < 1e-8:
		return
	hip_shift = off
	var bi := skel.find_bone("pelvis")
	var par := skel.get_bone_global_pose(skel.get_bone_parent(bi)).basis
	skel.set_bone_pose_position(bi, skel.get_bone_pose_position(bi) + par.inverse() * off)

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
	last_dt = delta
	var yaw := global_rotation.y
	var dyaw := wrapf(yaw - plant_prev_yaw, -PI, PI)
	plant_prev_yaw = yaw
	if absf(dyaw) > 1.5:
		dyaw = 0.0
	if delta > 0.0:
		turn_w = lerpf(turn_w, dyaw / delta, 1.0 - exp(-delta * 10.0))
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
	spin = not moving and lock_prev[0] != null and lock_prev[1] != null and (pivoting or absf(plant_lag) > 0.03 \
		or (step_t[0] >= 0.0 and spin_h[0] != null) or (step_t[1] >= 0.0 and spin_h[1] != null))
	if not spin:
		spin_h = [null, null]
	spin_t = spin_t + delta if spin else 0.0
	if pivoting and not was_pivoting:
		# a new turn on the spot: the head leads first, then the inner foot
		spin_wait = 0.0
		if step_t[0] < 0.0 and step_t[1] < 0.0:
			last_step_foot = -1
	was_pivoting = pivoting
	if spin:
		_spin_turn(dyaw, lag0)
		return
	if pivoting:
		# still slowing out of the walk: the body keeps its heading until the steps on the spot take over
		plant_lag = clampf(lag0 - dyaw, -SPIN_LAG, SPIN_LAG)
	elif moving and n == 2:
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

## turning on the spot the steps carry the body round: while a foot steps, the body turns with it about a
## point between the standing foot's ball and its own middle (SPIN_CENTER; the root really moves a little, a
## pivot turn is not about the body's middle), in between it holds; the node's heading (the mover's) runs
## ahead by up to SPIN_LAG
func _spin_turn(dyaw: float, lag0: float) -> void:
	var yaw := global_rotation.y
	var body := yaw - dyaw + lag0
	var want := body
	var pa := _stand_point(-1)
	for i in 2:
		if step_t[i] >= 0.0 and spin_h[i] != null:
			var sh: Array = spin_h[i]
			want = lerp_angle(float(sh[0]), float(sh[1]), smoothstep(0.0, 1.0, clampf((step_t[i] + last_dt) / step_dur[i], 0.0, 1.0)))
			pa = sh[2]
	plant_lag = clampf(wrapf(want - yaw, -PI, PI), -SPIN_LAG, SPIN_LAG)
	var turn := dyaw + plant_lag - lag0
	var o := model.global_position
	o.y = pa.y
	var d := (pa - o) - (pa - o).rotated(Vector3.UP, turn)
	d.y = 0.0
	global_position += d
	prev_pos += d     # not walking: the gait does not see it
	plant_off = plant_off.lerp(Vector3.ZERO, 1.0 - exp(-last_dt * 2.0))
	model.rotation.y = PI + plant_lag
	model.position = model_base + global_basis.inverse() * plant_off
	for i in 2:
		var c: Variant = _contact(i)
		prev_at[i] = skel.global_transform * (c as Vector3) if c != null else null

## a turn on the spot still has steps to take (the body is not round yet, or a foot has to close up): the
## mover keeps turning on the spot until it is done
func spin_busy() -> bool:
	if not spin or spin_t > 3.0:
		return false
	if step_t[0] >= 0.0 or step_t[1] >= 0.0 or absf(wrapf(turn_ahead - plant_lag, -PI, PI)) > SPOT_END:
		return true
	for i in 2:
		if maxf(lock_c[i].length() / SPOT_C, absf(lock_yaw[i]) / SPOT_YAW) > 1.0:
			return true
	return false

## where foot i really stands (world): the ball, which a turn pivots on; between both feet for -1
func _stand_point(i: int) -> Vector3:
	if i < 0:
		return (_stand_point(0) + _stand_point(1)) * 0.5
	var lp: Array = lock_prev[i]
	return lp[1]

## stroll, walk and run share one phase, but their stances do not line up (a walk foot is still down when the
## run one has long pushed off), so while the mix moves the blended stance foot would be dragged along. Per
## clip, sampled at load: per foot [heel z, heel y, toe z, toe y] by phase (skeleton space).
const GAIT_N := 64
var gait_tab := {}

func _build_gait_tables() -> void:
	var keep := [phase, run_k, move_w, act_w, walk_k]
	for c in ["stroll", "walk", "run"]:
		var rows: Array = []
		for k in GAIT_N:
			phase = float(k) / GAIT_N
			run_k = 1.0 if c == "run" else 0.0
			walk_k = 0.0 if c == "stroll" else 1.0
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
	phase = keep[0]; run_k = keep[1]; move_w = keep[2]; act_w = keep[3]; walk_k = keep[4]

## the gait mix: (stroll 0 -> walk 1, walk 0 -> run 1)
func _mix() -> Vector2:
	return Vector2(walk_k, run_k)

## stride of the current mix (m)
func _stride() -> float:
	var ws := lerpf(float(clips["stroll"]["stride"]), float(clips["walk"]["stride"]), walk_k)
	return lerpf(ws, float(clips["run"]["stride"]), run_k) * SCALE

## blended [heel z, heel y, toe z, toe y] of foot i at phase p and gait mix k
func _gait_at(i: int, p: float, k: Vector2) -> Array:
	var f := fposmod(p, 1.0) * GAIT_N
	var a := int(f) % GAIT_N
	var b := (a + 1) % GAIT_N
	var u := f - floorf(f)
	var sl: Array = gait_tab["stroll"]
	var w: Array = gait_tab["walk"]
	var r: Array = gait_tab["run"]
	var out: Array = []
	for j in 4:
		var vs := lerpf(float(sl[a][i * 4 + j]), float(sl[b][i * 4 + j]), u)
		var vw := lerpf(float(w[a][i * 4 + j]), float(w[b][i * 4 + j]), u)
		var vr := lerpf(float(r[a][i * 4 + j]), float(r[b][i * 4 + j]), u)
		out.append(lerpf(lerpf(vs, vw, k.x), vr, k.y))
	return out

## z of foot i's planted point at (p, k): heel, toe pad or between them as in _foot_lock; null when lifted.
## `kind` (0 heel, 1 toe, 2 both) pins the point when given.
func _plant_z(i: int, p: float, k: Vector2, kind := -1) -> Variant:
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
## (skeleton units), so a changing stroll / walk / run mix does not drag it; the plain stride rate otherwise
func _stance_advance(adv: float, k0: Vector2, fwd: float) -> float:
	if gait_tab.is_empty() or (_mix() - k0).length() < 1e-5:
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
	var prev_f := float(_plant_z(best, phase, _mix(), kind)[0]) - target
	if prev_f <= 0.0:
		return 0.0
	var n := 16
	for j in range(1, n + 1):
		var q := phase + span * j / n
		var f := float(_plant_z(best, q, _mix(), kind)[0]) - target
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
	var req := _step_request(on, delta)
	for i in 2:
		var lb: Array = legs[i]
		var ct: Array = contacts[i]
		if jumped:
			lock_c[i] = Vector3.ZERO; lock_yaw[i] = 0.0; lock_on[i] = false; lock_prev[i] = null
			step_t[i] = -1.0; pivot_w[i] = 0.0
		var F := skel.get_bone_global_pose(lb[2])
		var B := skel.get_bone_global_pose(lb[3])
		F.origin -= hip_shift
		B.origin -= hip_shift
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
			var on_ball := td and (pivot_w[i] > 0.0 or heel_up[i] > 0.0 or not hd)
			# position: the planted point (heel, toe pad or both) back where it was
			var pa: Vector3 = toe if on_ball else (heel if not td else (heel + toe) * 0.5)
			var was: Vector3 = pv[1] if on_ball else (pv[0] if not td else ((pv[0] as Vector3) + (pv[1] as Vector3)) * 0.5)
			var now := Basis(Vector3.UP, lock_yaw[i]) * (pa - A) + A + lock_c[i]
			var d := Si.basis * (was - S * now)
			d.y = 0.0
			# a foot coming down out of the air is pinned where it touches (pinning it to where it was in the
			# air a frame ago would yank it back); one already on the ground keeps its spot
			if lock_on[i] or was_down[i]:
				lock_c[i] += d
			lock_on[i] = true
			var dA := Vector3.ZERO
			if not pivoting and not spin:
				var R0 := Basis(Vector3.UP, lock_yaw[i])
				var hu := _heel_need(i, A, R0 * (heel - A) + A + lock_c[i], R0 * (toe - A) + A + lock_c[i])
				heel_up[i] = maxf(hu[0], move_toward(heel_up[i], 0.0, delta * 3.0))
				dA = hu[1] if float(hu[0]) >= heel_up[i] - 1e-4 else Vector3.ZERO
			if not pivoting and not spin and _needs_step(i, A, dA):
				# the body has got too far from the planted foot (a flick of the stick): a quick step, turned
				# a little into the turn
				_start_step(i, Vector3.ZERO, clampf(turn_ahead * 0.4, -0.3, 0.3), STEP_DUR, STEP_LIFT)
				steps_taken += 1
				planted = false
			elif not pivoting and not spin:
				_ease_overreach(i, A, dA)
		var fa := S.basis * (B.origin - A)
		var ha := atan2(fa.x, fa.z)
		if req == i and step_t[i] < 0.0:
			# turning on the spot / squaring up: this foot steps round to where it stands once the body has
			# turned `lead` over the other foot (an even share of what is left, so a half turn is: open, turn,
			# close); the spot is fixed in the world, so the turning body does not drag the foot on its way down
			var rem := wrapf(turn_ahead - plant_lag, -PI, PI) if spin else 0.0
			var lead := 0.0
			if absf(rem) > SPOT_END:
				lead = rem / ceilf(absf(rem) / SPOT_LEAD)
			var Pw := S * A
			var O := _stand_point(1 - i).lerp(global_position, SPIN_CENTER)
			O.y = Pw.y
			_start_step(i, Vector3.ZERO, 0.0, SPOT_DUR if lead != 0.0 else SPOT_DUR * 0.8, SPOT_LIFT if spin else SPOT_LIFT * 0.7)
			step_world[i] = [S * (A + lock_c[i]), ha + lock_yaw[i], O + Basis(Vector3.UP, lead) * (Pw - O), ha + lead]
			var body := global_rotation.y + plant_lag
			spin_h[i] = [body, body + lead, O] if spin else null
			spot_steps += 1
			planted = false
		was_down[i] = hd or td
		var lift := 0.0
		if step_t[i] >= 0.0:
			lock_on[i] = false
			step_t[i] += delta
			var u := minf(step_t[i] / step_dur[i], 1.0)
			# across while it is up, down onto the new spot at the end
			var w := smoothstep(0.08, 0.85, u)
			if step_world[i] != null:
				var sw: Array = step_world[i]
				var P := (sw[0] as Vector3).lerp(sw[2], w)
				var c := Si * P - A
				c.y = 0.0
				lock_c[i] = c
				lock_yaw[i] = wrapf(lerp_angle(float(sw[1]), float(sw[3]), w) - ha, -PI, PI)
			else:
				lock_c[i] = (step_from[i][0] as Vector3).lerp(step_to[i][0], w)
				lock_yaw[i] = lerpf(float(step_from[i][1]), float(step_to[i][1]), w)
			lift = step_lift[i] * sin(PI * u)
			if u >= 1.0:
				step_t[i] = -1.0
		elif not planted:
			if lock_on[i] or swing_t[i] < 0.0:
				swing_t[i] = 0.0
				swing_from[i] = [lock_c[i], lock_yaw[i]]
			lock_on[i] = false
			swing_t[i] += delta
			# a swinging foot sheds its correction by the time it lands (predicted from the gait table), so
			# every stance starts on the animated footfall instead of carrying the last one's offset along
			var u := 1.0 - exp(-swing_t[i] * 10.0)
			var left := _time_to_contact(i)
			if left >= 0.0:
				u = maxf(u, swing_t[i] / maxf(swing_t[i] + left, 1e-4))
			var w := 1.0 - smoothstep(0.0, 1.0, u)
			lock_c[i] = (swing_from[i][0] as Vector3) * w
			lock_yaw[i] = float(swing_from[i][1]) * w + _turn_aim() * (1.0 - w)
		if not planted:
			heel_up[i] = move_toward(heel_up[i], 0.0, delta * 4.0)
		var R := Basis(Vector3.UP, lock_yaw[i])
		var heel_c := R * (heel - A) + A + lock_c[i]
		var toe_c := R * (toe - A) + A + lock_c[i]
		var ankle := A + lock_c[i]
		var fb := R * F.basis
		if lift > 0.0:
			heel_c.y += lift; toe_c.y += lift; ankle.y += lift
		if pivot_w[i] > 0.0 or heel_up[i] > 0.0:
			var fwd := toe_c - heel_c
			fwd.y = 0.0
			var Rp := Basis(Vector3.UP.cross(fwd).normalized(), maxf(PIVOT_LIFT * smoothstep(0.0, 1.0, pivot_w[i]), heel_up[i]))
			ankle = toe_c + Rp * (ankle - toe_c)
			heel_c = toe_c + Rp * (heel_c - toe_c)
			fb = Rp * fb
			pivot_w[i] = move_toward(pivot_w[i], 0.0, delta * 4.0)
		if lock_c[i].length_squared() > 1e-10 or absf(lock_yaw[i]) > 1e-5 or pivot_w[i] > 0.0 or heel_up[i] > 0.0 or lift > 0.0 or hip_shift != Vector3.ZERO:
			_leg_ik(lb, ankle, fb, R)
		var hw := S * heel_c
		var tw := S * toe_c
		var fw2 := S.basis * (R * (B.origin - A))
		lock_prev[i] = [hw, tw, atan2(fw2.x, fw2.z)]
		if hd and td and step_t[i] < 0.0 and not flat_sent[i]:
			flat_sent[i] = true
			if anim == "move" and move_w > 0.5:
				foot_flat.emit(i)
		elif not hd and not td:
			flat_sent[i] = false

## the body has got too far from a planted foot (a flick of the stick): the leg is nearly straight, or the
## foot is far off its animated spot
## a leg just past full stretch with the foot only a little off: no step for that, it gives a hair
## (the heel is about to come up anyway), at most SLIP a frame
func _ease_overreach(i: int, A: Vector3, dA: Vector3) -> void:
	var c: Vector3 = lock_c[i]
	if c.length() < 0.005:
		return
	var lb: Array = legs[i]
	var H := skel.get_bone_global_pose(lb[0]).origin
	var K := skel.get_bone_global_pose(lb[1]).origin
	var ln := H.distance_to(K) + K.distance_to(A)
	var over := (A + c + dA - H).length() - 0.985 * ln
	if over > 0.0:
		lock_c[i] = c * (1.0 - minf(minf(over, SLIP) / c.length(), 1.0))

func _needs_step(i: int, A: Vector3, dA: Vector3) -> bool:
	var c: Vector3 = lock_c[i]
	if c.length() < 0.05:
		return false
	if c.length() > STEP_FAR:
		return true
	var lb: Array = legs[i]
	var H := skel.get_bone_global_pose(lb[0]).origin
	var K := skel.get_bone_global_pose(lb[1]).origin
	var ln := H.distance_to(K) + K.distance_to(A)
	var r := (A + c + dA - H).length() / ln
	if r > 1.0 or (r > 0.99 and c.length() > 0.095):
		return true
	return c.length() > 0.1 and r > STEP_REACH and r > (A - H).length() / ln + 0.05

## a trailing leg the lock stretches past HEEL_FROM (or past its animated stretch, if that is more) rolls up onto
## the ball, as at push-off, before it would need a step: [heel angle that brings it back within that (at most
## HEEL_UP), how far that moves the ankle]
func _heel_need(i: int, A: Vector3, heel_c: Vector3, toe_c: Vector3) -> Array:
	if anim != "move" or move_w < 0.5:
		return [0.0, Vector3.ZERO]
	var lb: Array = legs[i]
	var H := skel.get_bone_global_pose(lb[0]).origin
	var K := skel.get_bone_global_pose(lb[1]).origin
	var ln := H.distance_to(K) + K.distance_to(A)
	var ank := A + lock_c[i]
	var fwd := toe_c - heel_c
	fwd.y = 0.0
	# only what the lock adds: a stance leg straightening as animated (to ~15 deg of knee) is left alone
	var lim := maxf(HEEL_FROM, minf((A - H).length() / ln, 0.985)) * ln
	if (ank - H).length() <= lim or (H - ank).dot(fwd) <= 0.0:
		return [0.0, Vector3.ZERO]
	var ax := Vector3.UP.cross(fwd).normalized()
	var p := toe_c + Basis(ax, HEEL_UP) * (ank - toe_c)
	if (p - H).length() > lim:
		return [HEEL_UP, p - ank]
	# the least heel angle that does it (bisected: a stepped search pops the knee from frame to frame)
	var lo := 0.0
	var hi := HEEL_UP
	for k in 12:
		var a := (lo + hi) * 0.5
		if (toe_c + Basis(ax, a) * (ank - toe_c) - H).length() <= lim:
			hi = a
		else:
			lo = a
	p = toe_c + Basis(ax, hi) * (ank - toe_c)
	return [hi, p - ank]

## the twist a foot comes down with while walking / running round a bend: turned into the turn by a little
## over half of what the body will turn while it is down, so over its stance it goes from toed-in to toed-out
func _turn_aim() -> float:
	if anim != "move" or move_w < 0.5 or pivoting or phase_rate < 0.05:
		return 0.0
	var stance := lerpf(lerpf(float(clips["stroll"]["duty"]), float(clips["walk"]["duty"]), walk_k), float(clips["run"]["duty"]), run_k) / phase_rate
	return clampf(turn_w * stance * 0.6, -TURN_AIM, TURN_AIM)

func _start_step(i: int, to_c: Vector3, to_yaw: float, dur: float, lift: float) -> void:
	step_t[i] = 0.0
	step_from[i] = [lock_c[i], lock_yaw[i]]
	step_to[i] = [to_c, to_yaw]
	step_dur[i] = dur
	step_lift[i] = lift
	step_world[i] = null
	flat_sent[i] = false
	last_step_foot = i

## which foot (if any) starts a step on the spot this frame: while turning on the spot the feet take turns,
## inner foot first, once either one is twisted or stretched enough; standing still after a turn or a stop,
## a foot left badly twisted or stretched squares up
func _step_request(on: bool, delta: float) -> int:
	if step_t[0] >= 0.0 or step_t[1] >= 0.0 or not on:
		return -1
	idle_still = idle_still + delta if anim == "idle" and not spin else 0.0
	if spin:
		if not (lock_on[0] and lock_on[1]):
			spot_gap = 0.0
			return -1
		spot_gap += delta
		if spot_gap < SPOT_GAP:
			return -1
		# the feet take turns, inner foot first (after a moment for the head to lead); once the body is round,
		# the foot left behind closes up
		var rem := wrapf(turn_ahead - plant_lag, -PI, PI)
		if absf(rem) > SPOT_END:
			if last_step_foot < 0:
				spin_wait += delta
				if spin_wait < SPOT_WAIT:
					return -1
			return (1 - last_step_foot) if last_step_foot >= 0 else (0 if rem > 0.0 else 1)
		var worst := -1
		var wv := 1.0
		for i in 2:
			var v := maxf(lock_c[i].length() / SPOT_C, absf(lock_yaw[i]) / SPOT_YAW) + (0.5 if i != last_step_foot else 0.0)
			if v > wv:
				wv = v
				worst = i
		return worst
	spin_wait = 0.0
	last_step_foot = -1
	if anim == "idle" and idle_still > 0.25:
		var worst := -1
		var wv := 1.0
		for i in 2:
			var v := maxf(lock_c[i].length() / 0.07, absf(lock_yaw[i]) / 0.35)
			if lock_on[i] and v > wv:
				wv = v
				worst = i
		return worst
	return -1

## seconds until foot i touches down again at the current gait rate, or -1 when not walking / running
func _time_to_contact(i: int) -> float:
	if anim != "move" or move_w < 0.5 or gait_tab.is_empty() or phase_rate < 0.05:
		return -1.0
	for j in range(1, GAIT_N):
		var q := phase + float(j) / GAIT_N
		if _plant_z(i, q, _mix()) != null:
			return float(j) / GAIT_N / phase_rate
	return -1.0

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
	# the head attachment would only catch up with this tick's pose in the skeleton's deferred update:
	# put it on the head now, so nothing (the sim, a probe, a frame drawn in between) sees a stale hat
	if hat.get_parent() != hat_head_parent:
		hat.reparent(hat_head_parent, false)
	hat_head_parent.transform = skel.get_bone_global_pose(head_bone)
	hat.transform = hat_seat()
	var pel := (parts["pelvis"] as Node3D).global_position
	var lp := to_local(pel)
	blob.position = Vector3(lp.x * 0.6, 0.012, lp.z * 0.6)

func _setup_hat_seats() -> void:
	var mi := hat as MeshInstance3D
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# the brim (tipped back a little on his head): its plane through the front, back and side of the rim
	var pf := Vector3(0, 0, -INF)
	var pb := Vector3(0, 0, INF)
	var ps := Vector3(-INF, 0, 0)
	for v in verts:
		pf = v if v.z > pf.z else pf
		pb = v if v.z < pb.z else pb
		ps = v if v.x > ps.x else ps
	var up := (pf - pb).cross(ps - pb).normalized()
	up = -up if up.y < 0.0 else up
	hat_band_c = (pf + pb) * 0.5
	var fwd := ((pf - pb) - up * (pf - pb).dot(up)).normalized()
	# the hat mesh keeps its rest-pose vertex positions, so in skeleton rest space the seat on his head is
	# the identity. Over his face: tipped forward (crown out of the face, front of the brim at his chin),
	# brim flat 10 cm in front of the head bone, centred on the nose: nose, fringe and glasses are inside the
	# crown, the chin / forehead / cheeks outside it are all lower (head-frame z <= 0.093)
	var hr := skel.get_bone_global_rest(head_bone)
	var fb := _frame_rot(up, fwd, hr.basis.z, -hr.basis.y)
	hat_face_xf = hr.affine_inverse() * Transform3D(fb, hr * Vector3(0, 0.03, 0.10) - fb * hat_band_c)
	for sd: String in ["l", "r"]:
		# the grip: the brim by his temple (the front of it is out of reach of a hand on the head), fingers
		# in over the top of it, palm down on it, the wrist just outside the edge
		var d := Vector3((1.0 if sd == "l" else -1.0) * sin(1.05), 0.0, cos(1.05))
		var edge := hat_band_c
		for v in verts:
			if (v - hat_band_c).dot(d) > (edge - hat_band_c).dot(d):
				edge = v
		var f := (-d - up * 0.35).normalized()
		hat_grip[sd] = [edge - f * 0.065 + up * 0.022, f, -up]
		var names := ["clavicle_", "upperarm_", "lowerarm_", "hand_", "deltoid_"].map(func(n: String) -> int: return skel.find_bone(n + sd))
		arm_bones[sd] = names
		var hr2 := skel.get_bone_global_rest(names[3])
		var fw := (skel.get_bone_global_rest(skel.find_bone("middle_01_" + sd)).origin - hr2.origin).normalized()
		var ac := (skel.get_bone_global_rest(skel.find_bone("index_01_" + sd)).origin - skel.get_bone_global_rest(skel.find_bone("pinky_01_" + sd)).origin).normalized()
		var palm := ac.cross(fw) if sd == "r" else fw.cross(ac)
		hand_loc[sd] = [hr2.basis.inverse() * fw, hr2.basis.inverse() * palm]

## where the hat sits on the head bone: on his head (s 0), over his face (s 1), in between along an arc out
## and up, away from his face, turning as it goes
func hat_seat(s := -1.0) -> Transform3D:
	var u := smoothstep(0.0, 1.0, hat_s if s < 0.0 else s)
	if u <= 0.0:
		return hat_head_xf
	# a rigid brim cannot lie flat in the dip of a hammock or against a backrest: it rests tipped on that side
	var c := hat_face_xf * hat_band_c
	var face := Transform3D(Basis(Vector3.UP, -hat_tip), c) * Transform3D(Basis(), -c) * hat_face_xf * Transform3D(Basis(), hat_shift)
	if u >= 1.0:
		return face
	var b := Basis(hat_head_xf.basis.get_rotation_quaternion().slerp(face.basis.get_rotation_quaternion(), u))
	var p := (hat_head_xf * hat_band_c).lerp(face * hat_band_c, u) + Vector3(0, 0.55, 0.85).normalized() * HAT_LIFT * sin(PI * u)
	return Transform3D(b, p - b * hat_band_c)

## lying down / getting up (lie_k 0..1 either way): which hand, how far the hat is over his face, how firmly
## the hand is on the brim
func _hat_for(kind: String, lie_k: float) -> void:
	if kind == "seat" or lie_k <= 0.0:
		hat_s = 0.0
		hat_hold = 0.0
		return
	# on the bench / log the right hand props him on the seat while he lies back
	hat_side = "l" if kind == "seatlie" else "r"
	hat_tip = HAT_TIP.get(kind, 0.0)
	hat_shift = HAT_SHIFT.get(kind, Vector3.ZERO)
	var hl: Array = HAT_LIE.get(kind, HAT_LIE[""])
	hat_s = smoothstep(hl[1], hl[2], lie_k)
	hat_hold = smoothstep(hl[0], hl[1], lie_k) * (1.0 - smoothstep(hl[3], hl[4], lie_k))

## the holding hand on the front of the brim (two-bone arm IK, blended in by hat_hold)
func _hat_hands() -> void:
	if hat_hold <= 0.0:
		return
	var b: Array = arm_bones[hat_side]
	var hx := skel.get_bone_global_pose(head_bone) * hat_seat()
	var g: Array = hat_grip[hat_side]
	var hl: Array = hand_loc[hat_side]
	var want := _frame_rot(hl[0], hl[1], hx.basis * (g[1] as Vector3), hx.basis * (g[2] as Vector3))
	var Hg := skel.get_bone_global_pose(b[3])
	var w := smoothstep(0.0, 1.0, hat_hold)
	var wrist := Hg.origin.lerp(hx * (g[0] as Vector3), w)
	var hand_b := Basis(Hg.basis.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), w))
	# elbow out to the side and down, as when reaching up to the face
	var chest := skel.get_bone_global_pose(skel.get_bone_parent(b[0])).basis
	var pole := chest * Vector3(-1.0 if hat_side == "r" else 1.0, -0.7, -0.2)
	_arm_ik(b, wrist, hand_b, pole, w)

## two-bone arm IK (skeleton space): wrist to `wrist`, hand to `hand_b`; the elbow turns from where the clip
## has it towards `pole` by `w`. The deltoid helper stays half way between collar bone and upper arm.
func _arm_ik(b: Array, wrist: Vector3, hand_b: Basis, pole: Vector3, w: float) -> void:
	var U := skel.get_bone_global_pose(b[1])
	var L := skel.get_bone_global_pose(b[2])
	var W := skel.get_bone_global_pose(b[3]).origin
	var S := U.origin
	var E := L.origin
	var l1 := S.distance_to(E)
	var l2 := E.distance_to(W)
	var to := wrist - S
	var dist := clampf(to.length(), absf(l1 - l2) + 1e-4, (l1 + l2) * 0.9999)
	var u := to.normalized()
	var sw := (W - S).normalized()
	var cur := (E - S) - sw * (E - S).dot(sw)
	var pl := pole.normalized()
	if cur.length_squared() > 1e-10:
		pl = cur.normalized().slerp(pl, w) if absf(cur.normalized().dot(pl)) < 0.999 else pl
	var v := (pl - u * pl.dot(u)).normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var E2 := S + u * a + v * sqrt(maxf(l1 * l1 - a * a, 0.0))
	var W2 := S + u * dist
	var n_old := (E - S).cross(W - E)
	var n_new := (E2 - S).cross(W2 - E2)
	if n_old.length_squared() < 1e-12 or n_new.length_squared() < 1e-12:
		n_old = U.basis.x
		n_new = U.basis.x
	var Ub := _frame_rot(E - S, n_old, E2 - S, n_new) * U.basis
	var Lb := _frame_rot(W - E, n_old, W2 - E2, n_new) * L.basis
	var Pg := skel.get_bone_global_pose(b[0]).basis
	var up_q := (Pg.inverse() * Ub).get_rotation_quaternion()
	skel.set_bone_pose_rotation(b[1], up_q)
	skel.set_bone_pose_rotation(b[2], (Ub.inverse() * Lb).get_rotation_quaternion())
	skel.set_bone_pose_rotation(b[3], (Lb.inverse() * hand_b).get_rotation_quaternion())
	if b[4] >= 0:
		skel.set_bone_pose_rotation(b[4], skel.get_bone_rest(b[1]).basis.get_rotation_quaternion().slerp(up_q, 0.5))

## the hat's pose relative to the head bone
func hat_on_head() -> Transform3D:
	var head := skel.global_transform * skel.get_bone_global_pose(head_bone)
	return head.affine_inverse() * hat.global_transform

## how far the hat is off the seat it should be in (hat_seat()): [metres (crown centre moved + turn at the
## brim edge), radians]
func hat_offset_error() -> Vector2:
	var now := hat_on_head()
	var want := hat_seat()
	var c := (hat as MeshInstance3D).get_aabb().get_center()
	var ang := (want.basis.inverse() * now.basis).get_rotation_quaternion().get_angle()
	return Vector2((now * c).distance_to(want * c) + ang * 0.2, ang)

## the holding hand's knuckles to the brim grip [m] (INF while no hand holds the hat)
func hat_grip_gap() -> float:
	if hat_hold < 0.999:
		return INF
	var hx := skel.get_bone_global_pose(head_bone) * hat_seat()
	var g: Array = hat_grip[hat_side]
	var knuckle := skel.get_bone_global_pose(skel.find_bone("middle_01_" + hat_side)).origin
	var want := hx * ((g[0] as Vector3) + (g[1] as Vector3) * 0.085)
	return knuckle.distance_to(want) * skel.global_transform.basis.get_scale().x

# expression -> morph weights (MakeHuman expression units baked in Blender, see art/boy/face.py)
const EXPR := {
	"smile": {"smile": 0.5, "open": 0.0, "blink": 0.02},
	"laugh": {"smile": 1.0, "open": 0.42, "squint": 0.55, "brow_up": 0.35},
	"run": {"smile": 0.75, "open": 0.14, "squint": 0.2},
	"oops": {"brow_in": 0.9, "frown": 0.3, "open": 0.2, "brow_up": 0.25},
	"grit": {"brow_down": 0.5, "squint": 0.3, "press": 0.45, "smile": 0.15},
	"sleep": {"blink": 1.0, "smile": 0.3, "open": 0.03},
	"relax": {"blink": 1.0, "smile": 0.4},
}

## blink: lids down fast (70 ms), a short hold, up slower; every 2-5 s, now and then twice
func _blink_k(delta: float) -> float:
	blink_timer -= delta
	if blink_timer < 0.0 and blink_t < 0.0:
		blink_t = 0.0
	if blink_t < 0.0:
		return 0.0
	blink_t += delta
	var k := 0.0
	if blink_t < 0.07:
		k = blink_t / 0.07
	elif blink_t < 0.1:
		k = 1.0
	elif blink_t < 0.24:
		k = 1.0 - (blink_t - 0.1) / 0.14
		k = k * k * (3.0 - 2.0 * k)
	else:
		blink_t = -1.0
		blink_twice = not blink_twice and rng.randf() < 0.18
		blink_timer = 0.12 if blink_twice else rng.randf_range(2.0, 5.0)
	return k

func _update_face(delta: float) -> void:
	if head_mi == null:
		return
	var want: Dictionary = EXPR.get(expr, EXPR["smile"])
	var bk := _blink_k(delta)
	var rate := 1.0 if delta <= 0.0 else clampf(delta * 9.0, 0.0, 1.0)
	for n: String in morph:
		morph[n] = lerpf(morph[n], float(want.get(n, 0.0)), rate)
		var v: float = morph[n]
		if n == "blink":
			v = maxf(v, bk * (1.0 - float(morph.get("squint", 0.0)) * 0.3))
		head_mi.set_blend_shape_value(morph_idx[n], v)

# ------------------------------------------------------------------ dev helpers

## Freeze a named pose (screenshots / tests). Returns the pelvis in boy space.
func debug_pose(kind: String, p := 1.0, tt := 0.3) -> Vector3:
	frozen = true
	stance = "crouch" if kind.ends_with("_c") else "stand"
	act_w = 1.0
	ab_w = 0.0
	cur_slot = 0
	hat_s = 1.0 if kind == "sleep" or kind == "sun" else 0.0
	hat_tip = HAT_TIP.get(kind, 0.0)
	hat_shift = HAT_SHIFT.get(kind, Vector3.ZERO)
	hat_hold = 0.0
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
			act_w = 0.0; move_w = 1.0; run_k = 1.0 if kind == "run" else 0.0; walk_k = 1.0; phase = tt
		"sleep", "sun":
			var c := "hammock_sleep" if kind == "sleep" else "sun_rest"
			_set_slot(0, c, tt)
			glasses.visible = kind == "sun"
			e = "sleep" if kind == "sleep" else "relax"
		"sit_edge", "sit_ground":
			_set_slot(0, "hammock_sit" if kind == "sit_edge" else "sun_sit", 1.0)
		_:
			act_w = 0.0; move_w = 0.0; t_idle = tt
	expr = e
	_apply_mixer()
	_hat_hands()
	_update_props()
	blink_timer = 9.0
	_update_face(0.0)
	return pel
