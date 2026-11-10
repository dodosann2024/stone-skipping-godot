class_name Boy
extends Node3D
## The straw-hat boy (v5). Procedural skeleton: pelvis / spine / head, 2-bone IK arms and legs.
## Feet are anchored in world space: a planted foot never slides, also while turning or accelerating.
## Animations: idle (breathing, weight shifts), walk / run gait cycle (stride matched to ground speed),
## standing / half-kneeling sidearm throw with a kinetic chain and recovery step, reactions (cheer hops),
## and "activity" poses (sit / lie) driven by main.gd for the hammock and the beach towel.
## Faces -Z, right hand = +X, root at the feet.

signal released
signal footstep(side: int, running: bool)

const UARM := 0.17
const FARM := 0.16
const THIGH := 0.25
const SHIN := 0.24
const ANKLE_H := 0.062
const PEL_H := 0.555
const SHOULDER := Vector3(0.122, 0.262, 0.0)
const HIP := Vector3(0.072, -0.025, 0.0)
const STONE_OFF := Vector3(0.0, -0.08, -0.02)
const T_RELEASE := 0.15
const T_FOLLOW := 0.44
const T_HOLD := 0.85
const T_SETTLE := 1.55
const IDLE_L := Vector3(-0.085, 0, -0.015)
const IDLE_R := Vector3(0.085, 0, 0.015)
const LEG_MAX := (THIGH + SHIN) * 0.985

var parts := {}
var mat: ShaderMaterial
var blob: MeshInstance3D
var t := 0.0
var anim := "idle"   # idle | charge | throw | react | move | activity
var anim_t := 0.0
var stance := "stand"   # stand | crouch (throwing stance)
var power := 0.0
var throw_power := 0.0
var react_kind := ""
var did_release := false
var cur := {}
var from_pose := {}
var release_stand := Vector3.ZERO
var release_crouch := Vector3.ZERO
var stone_visible := true
var expr := "smile"
var hat_mode := "head"   # head | chest | ground
var move_speed := 0.0
var wading := false
var eye_c := Vector3.ZERO

# feet: world-space anchors (the truth) and their local copies for the skeleton
var fw: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var fwy: Array[float] = [0.0, 0.0]
var foot_p: Array[Vector3] = [IDLE_L, IDLE_R]
var foot_yaw: Array[float] = [0.08, -0.08]
var foot_pitch: Array[float] = [0.0, 0.0]
var plant: Array[float] = [1.0, 1.0]
var reanchor := true
var pre_act: Array = []
var act_frames := 0

# root motion estimate
var prev_root := Vector3.ZERO
var prev_yaw := 0.0
var vel_s := Vector3.ZERO
var speed_s := 0.0
var yaw_rate := 0.0
var accel_f := 0.0

# gait
var gait_ph := 0.0
var gait_w := 0.0
var leg_swing: Array[bool] = [false, false]
var lift_w: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var lift_yaw: Array[float] = [0.0, 0.0]
var arm_z: Array[float] = [0.0, 0.0]
var run_k := 0.0

# single steps (idle re-stance, throw stance, recovery step)
var step_i := -1
var step_t := 0.0
var step_dur := 0.24
var step_arc := 0.05
var step_from := Vector3.ZERO
var step_to := Vector3.ZERO
var step_yaw0 := 0.0
var step_yaw1 := 0.0

var look_target := 0.0
var look_timer := 3.0
var blink_timer := 2.5
var hat_ang := Vector2.ZERO
var hat_vel := Vector2.ZERO
var vest_ang := 0.0
var vest_vel := 0.0
var head_prev := Vector3.ZERO
var head_vprev := Vector3.ZERO
var sp_prev := Vector3.ZERO
var sp_vprev := Vector3.ZERO
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 7
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/character.gdshader")
	eye_c = BoyMesh.eye_c()
	BoyMesh.build(self)
	(parts["hat"] as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parts["glasses"] as Node3D).visible = false
	for k in ["eyes", "eyes_closed", "mouth_smile", "mouth_grit", "mouth_laugh", "mouth_sleep", "mouth_oops"]:
		(parts[k] as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_blob()
	expr = ""
	cur = pose_idle()
	stance = "stand"
	release_stand = _release_point()
	stance = "crouch"
	release_crouch = _release_point()
	stance = "stand"
	_set_expr("smile")
	_apply(_skeleton(cur, foot_p, foot_yaw, foot_pitch, false), 1.0)

func add_part(name: String, b: MeshBuilder) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = b.commit()
	mi.material_override = mat
	add_child(mi)
	parts[name] = mi

## soft contact shadow on the ground under the kid (grounds him even where the shadow map is coarse)
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

func _release_point() -> Vector3:
	var st := throw_stance()
	var sk := _skeleton(pose_release(), st[0], st[1], [0.0, 0.55 if stance == "stand" else 1.25], true)
	return (sk["hand_r"] as Transform3D) * STONE_OFF

var release_local: Vector3:
	get:
		return release_crouch if stance == "crouch" else release_stand

# ------------------------------------------------------------------ public API

func set_idle() -> void:
	if anim == "charge" or anim == "move":
		anim = "idle"

func set_move(speed: float) -> void:
	move_speed = speed
	if speed > 0.05 and (anim == "idle" or anim == "react"):
		_start_gait()

func charge(p: float) -> void:
	if anim != "charge":
		anim = "charge"
		anim_t = 0.0
	power = p

func start_throw(p: float) -> void:
	throw_power = p
	from_pose = cur.duplicate()
	anim = "throw"
	anim_t = 0.0
	did_release = false

func react(kind: String) -> void:
	react_kind = kind
	from_pose = cur.duplicate()
	anim = "react" if kind != "" else "idle"
	anim_t = 0.0

func show_stone(v: bool) -> void:
	stone_visible = v
	(parts["stone"] as MeshInstance3D).visible = v

## stance feet for the current throwing stance: [[left, right], [yaw_l, yaw_r]]
func throw_stance() -> Array:
	if stance == "crouch":
		return [[Vector3(-0.1, 0, -0.25), Vector3(0.12, 0, 0.29)], [-0.2, -0.3]]
	return [[Vector3(-0.06, 0, -0.17), Vector3(0.17, 0, 0.13)], [-0.25, -0.7]]

# ------------------------------------------------------------------ poses

static func P(d: Dictionary) -> Dictionary:
	var base := {
		"pdy": 0.0, "pyaw": 0.0, "plean": 0.03, "proll": 0.0, "poff": Vector3.ZERO,
		"sy": 0.0, "sl": 0.02, "sr": 0.0, "hy": 0.0, "hd": 0.0, "hr": 0.0, "wr": 0.15,
		"rh": Vector3(0.16, -0.05, -0.04), "re": Vector3(0.3, 0.0, 1.0),
		"lh": Vector3(-0.16, -0.05, -0.03), "le": Vector3(-0.3, 0.0, 1.0),
		"rheel": 0.0, "lheel": 0.0, "hop": 0.0,
		"flp": IDLE_L, "frp": IDLE_R, "fly": 0.08, "fry": -0.08,
	}
	for k in d:
		base[k] = d[k]
	return base

func pose_idle() -> Dictionary:
	return P({})

func pose_charge(p: float) -> Dictionary:
	if stance == "crouch":
		return _mix(P({"pdy": -0.22, "pyaw": -0.22, "plean": 0.25, "proll": -0.03, "poff": Vector3(0.01, 0, 0.04),
			"sy": -0.2, "sl": 0.2, "sr": -0.12, "hy": 0.38, "hd": 0.05, "wr": 0.4,
			"rh": Vector3(0.27, -0.05, 0.1), "re": Vector3(0.1, -0.7, 1.0), "lh": Vector3(-0.17, 0.0, -0.2), "le": Vector3(-0.6, -1.0, 0.2), "rheel": 1.2}),
			P({"pdy": -0.275, "pyaw": -0.45, "plean": 0.32, "proll": -0.06, "poff": Vector3(0.03, 0, 0.06),
			"sy": -0.45, "sl": 0.3, "sr": -0.28, "hy": 0.8, "hd": 0.1, "wr": 0.75,
			"rh": Vector3(0.33, -0.03, 0.14), "re": Vector3(0.0, -0.6, 1.0), "lh": Vector3(-0.17, 0.05, -0.27), "le": Vector3(-0.5, -1.0, 0.3), "rheel": 1.25}), p)
	return _mix(P({"pdy": -0.045, "pyaw": -0.22, "plean": 0.1, "proll": -0.02, "poff": Vector3(0.02, 0, 0.025),
		"sy": -0.2, "sl": 0.12, "sr": -0.08, "hy": 0.36, "hd": 0.05, "wr": 0.4,
		"rh": Vector3(0.27, 0.0, 0.11), "re": Vector3(0.1, -0.7, 1.0), "lh": Vector3(-0.17, 0.06, -0.16), "le": Vector3(-0.6, -1.0, 0.2)}),
		P({"pdy": -0.13, "pyaw": -0.48, "plean": 0.17, "proll": -0.06, "poff": Vector3(0.05, 0, 0.055),
		"sy": -0.46, "sl": 0.26, "sr": -0.22, "hy": 0.82, "hd": 0.08, "wr": 0.75,
		"rh": Vector3(0.34, 0.09, 0.13), "re": Vector3(0.0, -0.6, 1.0), "lh": Vector3(-0.18, 0.16, -0.24), "le": Vector3(-0.5, -1.0, 0.3), "lheel": -0.1}), p)

func pose_release() -> Dictionary:
	if stance == "crouch":
		return P({"pdy": -0.255, "pyaw": 0.22, "plean": 0.36, "poff": Vector3(-0.02, 0, -0.02),
			"sy": 0.22, "sl": 0.38, "sr": -0.2, "hy": -0.42, "hd": 0.12, "wr": -0.55,
			"rh": Vector3(0.3, -0.07, -0.14), "re": Vector3(0.3, -0.8, 0.6), "lh": Vector3(-0.27, 0.04, 0.04), "le": Vector3(-0.6, -1.0, 0.0), "rheel": 1.25})
	return P({"pdy": -0.1, "pyaw": 0.24, "plean": 0.2, "poff": Vector3(-0.02, 0, -0.04),
		"sy": 0.22, "sl": 0.3, "sr": -0.16, "hy": -0.42, "hd": 0.1, "wr": -0.55,
		"rh": Vector3(0.3, 0.02, -0.13), "re": Vector3(0.3, -0.8, 0.6), "lh": Vector3(-0.26, 0.1, 0.03), "le": Vector3(-0.6, -1.0, 0.0),
		"rheel": 0.55})

func pose_follow(p: float) -> Dictionary:
	if stance == "crouch":
		return P({"pdy": -0.24, "pyaw": 0.45, "plean": lerpf(0.36, 0.46, p), "proll": 0.03, "poff": Vector3(-0.03, 0, -0.06),
			"sy": 0.38, "sl": lerpf(0.34, 0.48, p), "sr": 0.05, "hy": -0.75, "hd": -0.1, "wr": -0.3,
			"rh": Vector3(-0.07, 0.02, -0.21), "re": Vector3(0.6, -1.0, 0.0), "lh": Vector3(-0.3, 0.12, 0.1), "le": Vector3(-0.3, -1.0, 0.5), "rheel": 1.25})
	return P({"pdy": -0.07, "pyaw": 0.5, "plean": lerpf(0.22, 0.36, p), "proll": 0.04, "poff": Vector3(-0.045, 0, -0.1),
		"sy": 0.4, "sl": lerpf(0.25, 0.4, p), "sr": 0.05, "hy": -0.8, "hd": -0.12, "wr": -0.3,
		"rh": Vector3(-0.06, 0.08, -0.2), "re": Vector3(0.6, -1.0, 0.0), "lh": Vector3(-0.3, 0.16, 0.1), "le": Vector3(-0.3, -1.0, 0.5),
		"rheel": 0.7})

func pose_settle() -> Dictionary:
	if stance == "crouch":
		return P({"pdy": -0.2, "pyaw": 0.15, "plean": 0.25, "sy": 0.1, "sl": 0.15, "hy": -0.25, "hd": -0.05,
			"rh": Vector3(0.17, -0.05, -0.08), "lh": Vector3(-0.17, -0.04, -0.06), "rheel": 1.2})
	return P({"pdy": -0.015, "pyaw": 0.12, "plean": 0.08, "poff": Vector3(0.0, 0, -0.05), "sy": 0.08, "sl": 0.1, "hy": -0.2, "hd": -0.06, "wr": 0.1,
		"rh": Vector3(0.165, -0.04, -0.05), "lh": Vector3(-0.16, -0.04, -0.04)})

## settle stance after the recovery step (stand) / knee stays down (crouch)
func settle_stance() -> Array:
	if stance == "crouch":
		return throw_stance()
	return [[Vector3(-0.06, 0, -0.17), Vector3(0.09, 0, -0.1)], [-0.25, -0.3]]

## jump for joy: anticipation dip, three little hops with fists in the air, then waving
func pose_cheer(tt: float) -> Dictionary:
	var hop := 0.0
	var dip := 0.0
	for n in 3:
		var t0 := 0.22 + n * 0.46
		var x := (tt - t0) / 0.3
		if x > 0.0 and x < 1.0:
			hop = 0.085 * sin(PI * x) * (1.0 - n * 0.18)
		dip += 0.055 * exp(-pow((tt - t0 + 0.06) / 0.07, 2.0)) + 0.04 * exp(-pow((tt - t0 - 0.36) / 0.06, 2.0))
	var w := sin(tt * 16.0) * 0.04 * smoothstep(1.4, 1.7, tt)
	var up := smoothstep(0.08, 0.3, tt)
	return P({"pdy": -0.03 - dip, "hop": hop, "pyaw": 0.05, "plean": -0.03 + dip * 1.5, "sl": -0.05 + dip, "sr": w * 0.8, "hd": -0.28, "hr": w * 1.5, "wr": 0.0,
		"rh": Vector3(0.16, -0.05, -0.04).lerp(Vector3(0.3 + w, 0.55, -0.06), up), "re": Vector3(1.0, -0.3, 0.3),
		"lh": Vector3(-0.16, -0.05, -0.03).lerp(Vector3(-0.3 + w, 0.55, -0.06), up), "le": Vector3(-1.0, -0.3, 0.3)})

func pose_oops(tt: float) -> Dictionary:
	return P({"pdy": -0.04, "plean": 0.12, "sl": 0.12, "hy": sin(tt * 7.0) * 0.18 * smoothstep(0.3, 0.5, tt), "hd": 0.22, "wr": 0.0,
		"rh": Vector3(0.175, 0.44, 0.0), "re": Vector3(1.0, -0.4, 0.3), "lh": Vector3(-0.175, 0.44, 0.0), "le": Vector3(-1.0, -0.4, 0.3)})

# lying / sitting poses (boy space; main.gd rotates the root)
func pose_sit_edge() -> Dictionary:
	return P({"pdy": -0.2, "plean": 0.12, "sl": 0.08, "hd": 0.05,
		"rh": Vector3(0.2, -0.12, 0.04), "re": Vector3(0.4, 0, 1), "lh": Vector3(-0.2, -0.12, 0.04), "le": Vector3(-0.4, 0, 1),
		"flp": Vector3(-0.09, 0.0, -0.24), "frp": Vector3(0.09, 0.02, -0.22), "fly": 0.1, "fry": -0.1})

func pose_sit_edge_mid() -> Dictionary:
	return P({"pdy": -0.13, "plean": 0.45, "sl": 0.2, "hd": -0.15,
		"rh": Vector3(0.22, -0.2, 0.16), "re": Vector3(0.4, 0, -1), "lh": Vector3(-0.22, -0.2, 0.16), "le": Vector3(-0.4, 0, -1),
		"flp": Vector3(-0.09, 0.0, -0.12), "frp": Vector3(0.09, 0.0, -0.1), "fly": 0.1, "fry": -0.1})

func pose_sit_ground() -> Dictionary:
	return P({"pdy": -0.45, "plean": -0.1, "sl": 0.15, "hd": 0.08,
		"rh": Vector3(0.2, -0.18, 0.14), "re": Vector3(0.3, 0, -1), "lh": Vector3(-0.2, -0.18, 0.14), "le": Vector3(-0.3, 0, -1),
		"flp": Vector3(-0.085, -0.02, -0.4), "frp": Vector3(0.085, -0.02, -0.42), "fly": 0.1, "fry": -0.1, "lheel": -1.2, "rheel": -1.2})

func pose_sit_ground_mid() -> Dictionary:
	return P({"pdy": -0.32, "plean": 0.5, "sl": 0.25, "hd": -0.1,
		"rh": Vector3(0.2, -0.25, -0.12), "re": Vector3(0.4, 0, 1), "lh": Vector3(-0.2, -0.25, -0.12), "le": Vector3(-0.4, 0, 1),
		"flp": Vector3(-0.1, 0.0, -0.12), "frp": Vector3(0.1, 0.0, -0.1), "fly": 0.15, "fry": -0.15, "lheel": 0.3, "rheel": 0.3})

func pose_lie_sleep(tt: float) -> Dictionary:
	var br := sin(tt * 1.6) * 0.02
	return P({"pdy": -0.03, "plean": 0.2, "sl": 0.12 + br, "hd": -0.15, "hr": 0.12,
		"rh": Vector3(0.06, 0.08, -0.13), "re": Vector3(1, 0, 0), "lh": Vector3(-0.07, 0.11, -0.12), "le": Vector3(-1, 0, 0),
		"flp": Vector3(-0.07, 0.03, -0.12), "frp": Vector3(0.08, 0.05, -0.1), "fly": 0.25, "fry": -0.25})

func pose_lie_sun(tt: float) -> Dictionary:
	var br := sin(tt * 1.3) * 0.015
	var tap := maxf(sin(tt * 2.2), 0.0) * 0.06
	return P({"pdy": -0.01, "plean": 0.02, "sl": 0.03 + br, "hd": -0.2,
		"rh": Vector3(0.085, 0.47, 0.11), "re": Vector3(1.0, 0.3, -0.2), "lh": Vector3(-0.085, 0.47, 0.11), "le": Vector3(-1.0, 0.3, -0.2),
		"flp": Vector3(-0.045, 0.0, -0.01), "frp": Vector3(-0.03, 0.03, -0.08 - tap), "fly": 0.15, "fry": 0.3})

## half-way poses while lying back: propped on the arms, legs coming up
func pose_lie_mid(kind: String) -> Dictionary:
	if kind == "sleep":
		return P({"pdy": -0.12, "plean": -0.35, "sl": -0.1, "hd": 0.25,
			"rh": Vector3(0.24, -0.2, 0.12), "re": Vector3(0.6, 0, -1), "lh": Vector3(-0.24, -0.2, 0.12), "le": Vector3(-0.6, 0, -1),
			"flp": Vector3(-0.08, 0.1, -0.3), "frp": Vector3(0.08, 0.12, -0.28), "fly": 0.15, "fry": -0.15})
	return P({"pdy": -0.42, "plean": -0.45, "sl": -0.15, "hd": 0.3,
		"rh": Vector3(0.2, -0.3, 0.2), "re": Vector3(0.5, 0, -1), "lh": Vector3(-0.2, -0.3, 0.2), "le": Vector3(-0.5, 0, -1),
		"flp": Vector3(-0.07, -0.02, -0.4), "frp": Vector3(0.07, 0.04, -0.36), "fly": 0.1, "fry": -0.1, "lheel": -1.0, "rheel": -0.6})

static func _mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var o := {}
	for key in a:
		var va: Variant = a[key]
		var vb: Variant = b.get(key, va)
		if va is Vector3:
			o[key] = (va as Vector3).lerp(vb as Vector3, k)
		else:
			o[key] = lerpf(float(va), float(vb), k)
	return o

## quadratic Bezier through a middle key pose
static func _mix3(a: Dictionary, m: Dictionary, b: Dictionary, k: float) -> Dictionary:
	return _mix(_mix(a, m, k), _mix(m, b, k), k)

const G_BODY := ["pdy", "pyaw", "plean", "proll", "poff", "rheel", "lheel", "hop", "lh", "le"]
const G_SPINE := ["sy", "sl", "sr"]
const G_HEAD := ["hy", "hd", "hr"]
const G_ARM := ["rh", "re", "wr"]

## mix with a separate weight per body group (hips lead, then chest, then the throwing arm)
static func _mix_chain(a: Dictionary, b: Dictionary, kb: float, ks: float, kh: float, ka: float) -> Dictionary:
	var o := _mix(a, b, kb)
	for grp: Array in [[G_SPINE, ks], [G_HEAD, kh], [G_ARM, ka]]:
		var k: float = grp[1]
		for key: String in grp[0]:
			var va: Variant = a[key]
			if va is Vector3:
				o[key] = (va as Vector3).lerp(b[key] as Vector3, k)
			else:
				o[key] = lerpf(float(va), float(b[key]), k)
	return o

static func _ease_in(x: float) -> float:
	return x * x

static func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)

static func _sm(x: float) -> float:
	return smoothstep(0.0, 1.0, x)

# ------------------------------------------------------------------ activity (driven by main.gd)

## kind: "sleep" | "sun"; sit_k: 0 stand -> 1 seated; lie_k: 0 seated -> 1 lying. Returns the pelvis in boy space.
func activity(kind: String, sit_k: float, lie_k: float, tt: float) -> Vector3:
	if anim != "activity":
		pre_act = [cur.duplicate(), anim]
		act_frames = 0
		from_pose = cur.duplicate()
		from_pose["flp"] = foot_p[0]; from_pose["frp"] = foot_p[1]
		from_pose["fly"] = foot_yaw[0]; from_pose["fry"] = foot_yaw[1]
		from_pose["lheel"] = foot_pitch[0]; from_pose["rheel"] = foot_pitch[1]
		from_pose["hop"] = 0.0
	anim = "activity"
	step_i = -1
	var sit := pose_sit_edge() if kind == "sleep" else pose_sit_ground()
	var mid := pose_sit_edge_mid() if kind == "sleep" else pose_sit_ground_mid()
	var lie := pose_lie_sleep(tt) if kind == "sleep" else pose_lie_sun(tt)
	var stand: Dictionary = from_pose
	if lie_k <= 0.0:
		cur = _mix3(stand, mid, sit, _sm(sit_k)) if sit_k < 1.0 else sit
	else:
		cur = _mix3(sit, pose_lie_mid(kind), lie, _sm(lie_k))
	hat_mode = "head"
	if lie_k > 0.6:
		hat_mode = "chest" if kind == "sleep" else "ground"
	(parts["glasses"] as Node3D).visible = kind == "sun" and lie_k > 0.5
	blob.visible = sit_k < 0.3 and lie_k <= 0.0
	if kind == "sleep":
		_set_expr("sleep" if lie_k > 0.7 else "smile")
	else:
		_set_expr("relax" if lie_k > 0.5 else "smile")
	show_stone(false)
	var fp: Array = [cur["flp"], cur["frp"]]
	var fy: Array = [float(cur["fly"]), float(cur["fry"])]
	var fpi: Array = [float(cur["lheel"]), float(cur["rheel"])]
	var sk := _skeleton(cur, fp, fy, fpi, false)
	_apply(sk, 1.0)
	return (sk["pelvis"] as Transform3D).origin

func end_activity() -> void:
	hat_mode = "head"
	(parts["glasses"] as Node3D).visible = false
	blob.visible = true
	if act_frames == 0 and pre_act.size() == 2:
		# probed and released in the same frame (main.gd measures the seated pelvis): change nothing
		cur = pre_act[0]
		anim = "idle"
		_set_expr("smile")
		return
	anim = "idle"
	foot_p = [IDLE_L, IDLE_R]
	foot_yaw = [0.08, -0.08]
	foot_pitch = [0.0, 0.0]
	cur = pose_idle()
	reanchor = true

# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	_tick(delta)

func _root_yaw() -> float:
	return global_transform.basis.get_euler().y

func _to_local() -> void:
	var inv := global_transform.affine_inverse()
	var ry := _root_yaw()
	for i in 2:
		foot_p[i] = inv * fw[i]
		foot_yaw[i] = wrapf(fwy[i] - ry, -PI, PI)

func _anchor_from_local() -> void:
	var g := global_transform
	var ry := _root_yaw()
	for i in 2:
		fw[i] = g * Vector3(foot_p[i].x, 0.0, foot_p[i].z)
		fwy[i] = ry + foot_yaw[i]
	step_i = -1
	leg_swing = [false, false]

func _tick(delta: float) -> void:
	t += delta
	anim_t += delta
	if anim == "activity":
		act_frames += 1
		return
	var g := global_transform
	var ry := _root_yaw()
	if reanchor:
		reanchor = false
		_anchor_from_local()
		prev_root = g.origin
		prev_yaw = ry
	# root motion (from the node itself, so every mover - explore, throw walk, rest approach - plants feet right)
	var moved := g.origin - prev_root
	if moved.length() > 0.6:
		_anchor_from_local()
		moved = Vector3.ZERO
		vel_s = Vector3.ZERO
	if delta > 0.0:
		var v := Vector3(moved.x, 0, moved.z) / delta
		var old_f := vel_s.dot(-g.basis.z)
		vel_s = vel_s.lerp(v, 1.0 - exp(-delta * 14.0))
		accel_f = lerpf(accel_f, (vel_s.dot(-g.basis.z) - old_f) / delta, 1.0 - exp(-delta * 6.0))
		yaw_rate = lerpf(yaw_rate, wrapf(ry - prev_yaw, -PI, PI) / delta, 1.0 - exp(-delta * 8.0))
	speed_s = vel_s.length()
	prev_root = g.origin
	prev_yaw = ry

	var want: Dictionary
	var stance_l := IDLE_L
	var stance_r := IDLE_R
	var yaw_l := 0.08
	var yaw_r := -0.08
	var e := "smile"
	var step_d := 0.24
	var step_h := 0.05
	var tol := 0.06
	var blend := 6.0
	match anim:
		"charge":
			want = pose_charge(power)
			var st := throw_stance()
			stance_l = st[0][0]; stance_r = st[0][1]; yaw_l = st[1][0]; yaw_r = st[1][1]
			e = "grit" if power > 0.35 else "smile"
			tol = 0.025
			blend = 14.0
		"throw":
			want = _throw_pose(anim_t)
			var st := throw_stance() if anim_t < 0.22 else settle_stance()
			stance_l = st[0][0]; stance_r = st[0][1]; yaw_l = st[1][0]; yaw_r = st[1][1]
			e = "grit" if anim_t < T_FOLLOW else "smile"
			tol = 0.025
			step_d = 0.34
			step_h = 0.1
			blend = 0.0
			if not did_release and anim_t >= T_RELEASE:
				did_release = true
				show_stone(false)
				released.emit()
		"react":
			stance_l = foot_p[0]; stance_r = foot_p[1]
			yaw_l = foot_yaw[0]; yaw_r = foot_yaw[1]
			var rp := pose_cheer(anim_t) if react_kind == "cheer" else pose_oops(anim_t)
			var k := smoothstep(0.0, 0.25, anim_t) * (1.0 - smoothstep(2.3, 2.8, anim_t))
			var base := _mix(from_pose, _idle_pose(), smoothstep(0.0, 0.4, anim_t))
			want = _mix(base, rp, k)
			if react_kind == "cheer":
				want["hop"] = float(rp["hop"])
				stance_l = IDLE_L; stance_r = IDLE_R; yaw_l = 0.08; yaw_r = -0.08
			e = ("laugh" if react_kind == "cheer" else "oops") if k > 0.4 else "smile"
			blend = 14.0
			if anim_t > 2.8:
				anim = "idle"
		"move":
			gait_w = minf(gait_w + delta * 4.0, 1.0)
			want = _gait(delta)
			blend = 12.0
			if run_k > 0.6:
				e = "laugh"
			if move_speed < 0.05 and speed_s < 0.12:
				anim = "idle"
		_:
			want = _idle_pose()
			if not stone_visible:
				show_stone(true)
	if anim != "move":
		gait_w = 0.0
		run_k = 0.0
		leg_swing = [false, false]
		_update_feet(delta, [stance_l, stance_r], [yaw_l, yaw_r], tol, step_d, step_h)
	if blend <= 0.0:
		cur = want
	else:
		cur = _mix(cur, want, 1.0 - exp(-delta * blend))
		if anim == "react":
			cur["hop"] = float(want["hop"])
	_to_local()
	if anim != "move":
		foot_pitch = [float(cur["lheel"]), float(cur["rheel"])]
		if step_i >= 0:
			foot_pitch[step_i] += sin(PI * minf(step_t, 1.0)) * 0.25
	_set_expr(e)
	var sk := _skeleton(cur, foot_p, foot_yaw, foot_pitch, true)
	blink_timer -= delta
	var blink := 1.0
	if blink_timer < 0.12:
		blink = 0.12
		if blink_timer < 0.0:
			blink_timer = rng.randf_range(2.0, 4.5)
	_springs(delta, (sk["head"] as Transform3D).origin, (sk["spine"] as Transform3D).origin)
	_apply(sk, blink)
	var pel: Vector3 = (sk["pelvis"] as Transform3D).origin
	blob.position = Vector3(pel.x * 0.6, 0.012, pel.z * 0.6)

## breathing, slow weight shifts from foot to foot (contrapposto), looking around
func _idle_pose() -> Dictionary:
	var want := pose_idle()
	var br := sin(t * 2.0)
	var shift := smoothstep(-0.55, 0.55, sin(t * 0.42 + 1.0)) * 2.0 - 1.0
	want["sl"] = float(want["sl"]) + br * 0.016
	want["pdy"] = -0.012 + br * 0.003 - absf(shift) * 0.008
	want["poff"] = Vector3(shift * 0.022, 0, 0)
	want["proll"] = shift * 0.045
	want["sr"] = -shift * 0.04
	want["pyaw"] = shift * 0.05
	want["rh"] = Vector3(0.165, -0.05 + br * 0.004, -0.035 + shift * 0.01)
	want["lh"] = Vector3(-0.165, -0.05 + br * 0.004, -0.03 - shift * 0.01)
	look_timer -= get_process_delta_time()
	if look_timer < 0.0:
		look_timer = rng.randf_range(2.5, 5.5)
		look_target = [0.0, 0.55, -0.5, 0.0, 0.25][rng.randi() % 5]
	want["hy"] = look_target - shift * 0.05
	want["hd"] = -0.08 if absf(look_target) > 0.1 else 0.0
	want["hr"] = shift * 0.05
	return want

func _throw_pose(a: float) -> Dictionary:
	if a < T_RELEASE:
		# kinetic chain: hips lead, chest follows, the arm whips through last
		var kb := _sm(clampf(a / 0.11, 0.0, 1.0))
		var ks := _sm(clampf((a - 0.02) / 0.11, 0.0, 1.0))
		var ka := _ease_in(clampf((a - 0.035) / (T_RELEASE - 0.035), 0.0, 1.0))
		return _mix_chain(from_pose, pose_release(), kb, ks, ks, ka)
	var fol := pose_follow(throw_power)
	if a < T_FOLLOW:
		var x := (a - T_RELEASE) / (T_FOLLOW - T_RELEASE)
		return _mix_chain(pose_release(), fol, _ease_out(minf(x * 1.1, 1.0)), _ease_out(x), _sm(x), _ease_out(minf(x * 1.25, 1.0)))
	if a < T_HOLD:
		# balance after the follow-through: a little sway over the front foot
		var h := (a - T_FOLLOW) / (T_HOLD - T_FOLLOW)
		var f := fol.duplicate()
		f["plean"] = float(f["plean"]) - 0.05 * _sm(h) + 0.02 * sin(h * PI * 2.0)
		f["proll"] = float(f["proll"]) + 0.02 * sin(h * PI * 1.5)
		f["rheel"] = lerpf(float(f["rheel"]), 0.0, _sm(h * 3.5)) if stance == "stand" else float(f["rheel"])
		return f
	var settle := pose_settle()
	if a < T_SETTLE:
		var h2 := (a - T_HOLD) / (T_SETTLE - T_HOLD)
		var f2 := fol.duplicate()
		f2["plean"] = float(f2["plean"]) - 0.05
		f2["rheel"] = 0.0 if stance == "stand" else float(f2["rheel"])
		return _mix(f2, settle, _sm(h2))
	return settle

# ------------------------------------------------------------------ gait

func _start_gait() -> void:
	anim = "move"
	gait_w = 0.0
	# the foot that is further behind (relative to where we head) lifts first
	var duty := 0.6
	var dir := vel_s.normalized() if speed_s > 0.05 else -global_transform.basis.z
	var zl := (fw[0] - global_position).dot(dir)
	var zr := (fw[1] - global_position).dot(dir)
	gait_ph = duty - 0.03 if zl < zr else duty - 0.53
	gait_ph = fposmod(gait_ph, 1.0)
	leg_swing = [false, false]
	step_i = -1

## walk / run cycle. Stance feet stay where they landed; the swing foot flies to where the body will be.
func _gait(dt: float) -> Dictionary:
	var g := global_transform
	var ry := _root_yaw()
	var spd := speed_s
	run_k = lerpf(run_k, smoothstep(1.45, 2.35, spd), 1.0 - exp(-dt * 6.0))
	var rk := run_k
	var freq := lerpf(clampf(0.95 + 0.4 * spd, 0.95, 1.42), 1.72, rk)
	var duty := lerpf(0.61, 0.36, rk)
	if wading:
		freq *= 0.85
		duty = maxf(duty, 0.6)
	gait_ph = fposmod(gait_ph + dt * freq, 1.0)
	var travel := spd * duty / freq
	var half := minf(travel * 0.5, 0.36)
	var lift := lerpf(0.055, 0.12, rk) * (0.6 if wading else 1.0)
	var comp := 0.0
	for i in 2:
		var u := fposmod(gait_ph + (0.0 if i == 0 else 0.5), 1.0)
		var sx := -0.078 if i == 0 else 0.078
		var swing := u >= duty
		if swing and not leg_swing[i]:
			leg_swing[i] = true
			lift_w[i] = fw[i]
			lift_yaw[i] = fwy[i]
		var remain := (1.0 - u) / freq if swing else 0.0
		var yaw_td := ry + clampf(yaw_rate, -4.0, 4.0) * remain
		var tb := Basis(Vector3.UP, yaw_td)
		var tgt := g.origin + vel_s * remain + tb * Vector3(sx, 0, -half - 0.02)
		tgt.y = g.origin.y
		var toe := -0.05 if i == 0 else 0.05
		if not swing and leg_swing[i]:
			leg_swing[i] = false
			fw[i] = Vector3(fw[i].x, g.origin.y, fw[i].z)
			if gait_w > 0.5:
				footstep.emit(i, rk > 0.5)
		if swing:
			var s := (u - duty) / (1.0 - duty)
			var k := _sm(s)
			var p := lift_w[i].lerp(tgt, k)
			p.y = lerpf(lift_w[i].y, tgt.y, k) + lift * pow(sin(PI * minf(s * 1.08, 1.0)), 0.75)
			fw[i] = p
			fwy[i] = lerp_angle(lift_yaw[i], yaw_td + toe, k)
			foot_pitch[i] = lerpf(lerpf(0.55, 0.75, rk), lerpf(-0.22, 0.05, rk), _sm(s))
			plant[i] = smoothstep(0.75, 0.95, s)
		else:
			var s2 := u / duty
			comp = maxf(comp, sin(PI * s2))
			var strike := lerpf(-0.22, 0.05, rk) * (1.0 - smoothstep(0.0, 0.18, s2))
			var off := smoothstep(lerpf(0.55, 0.4, rk), 1.0, s2) * lerpf(0.55, 0.75, rk)
			foot_pitch[i] = strike + off
			plant[i] = 1.0
	_to_local()
	# upper body follows the legs
	var zl := foot_p[0].z
	var zr := foot_p[1].z
	arm_z[0] = lerpf(arm_z[0], zr, 1.0 - exp(-dt * 16.0))   # left arm swings with the right leg
	arm_z[1] = lerpf(arm_z[1], zl, 1.0 - exp(-dt * 16.0))
	var pyaw := clampf((zl - zr) * lerpf(0.42, 0.3, rk), -0.22, 0.22)
	var lean := lerpf(0.05, 0.19, rk) + clampf(accel_f * 0.035, -0.08, 0.14)
	var turn := clampf(yaw_rate * spd * 0.07, -0.22, 0.22)
	var sway := sin(TAU * (gait_ph - duty * 0.25)) * lerpf(0.018, 0.006, rk)
	var pdy := lerpf(0.004, -0.03, rk) - comp * lerpf(0.0, 0.045, rk) + (1.0 - comp) * lerpf(0.0, 0.02, rk)
	var hands: Array[Vector3] = []
	var poles: Array[Vector3] = []
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var amp := lerpf(1.95, 2.1, rk)
		var ang := clampf(-arm_z[i] * amp, -0.6, 0.9)
		var bend := lerpf(0.3, 1.45, rk) + maxf(ang, 0.0) * lerpf(0.55, 0.2, rk)
		var sh := Vector3(SHOULDER.x * side, SHOULDER.y, 0.0)
		var el := sh + Vector3(side * lerpf(0.03, 0.05, rk), -cos(ang) * UARM, -sin(ang) * UARM)
		var fa := ang + bend
		var hd := el + Vector3(-side * lerpf(0.0, 0.035, rk) * maxf(sin(fa), 0.0), -cos(fa) * FARM, -sin(fa) * FARM)
		hands.append(hd)
		poles.append(Vector3(0.35 * side, -0.2, 1.0))
	return P({"pdy": pdy, "pyaw": pyaw, "plean": lean, "proll": turn + sway, "poff": Vector3(-sway * 0.6, 0, 0),
		"sy": -pyaw * 1.35, "sl": lerpf(0.03, 0.1, rk), "sr": -sway * 0.8, "hy": pyaw * 0.35 + clampf(yaw_rate * 0.12, -0.35, 0.35), "hd": lerpf(0.0, -0.1, rk),
		"wr": 0.2, "rh": hands[1], "re": poles[1], "lh": hands[0], "le": poles[0]})

# ------------------------------------------------------------------ single steps

func _update_feet(delta: float, want_p: Array, want_yaw: Array, tol: float, dur: float, arc: float) -> void:
	var g := global_transform
	var ry := _root_yaw()
	plant = [1.0, 1.0]
	if step_i >= 0:
		step_t += delta / step_dur
		var k := _sm(minf(step_t, 1.0))
		var p := step_from.lerp(step_to, k)
		p.y += sin(PI * minf(step_t, 1.0)) * step_arc
		fw[step_i] = p
		fwy[step_i] = lerp_angle(step_yaw0, step_yaw1, k)
		plant[step_i] = smoothstep(0.7, 1.0, step_t)
		if step_t >= 1.0:
			fw[step_i] = step_to
			step_i = -1
		return
	var best := -1
	var worst := 0.0
	for i: int in [1, 0]:
		var tw: Vector3 = g * (want_p[i] as Vector3)
		var err := Vector2(fw[i].x - tw.x, fw[i].z - tw.z).length() + absf(wrapf(fwy[i] - ry - float(want_yaw[i]), -PI, PI)) * 0.12 + absf(fw[i].y - g.origin.y)
		if err > tol and err > worst:
			worst = err
			best = i
	if best >= 0:
		step_i = best
		step_t = 0.0
		step_dur = dur
		step_arc = arc
		step_from = fw[best]
		step_to = g * (want_p[best] as Vector3)
		step_to.y = g.origin.y
		step_yaw0 = fwy[best]
		step_yaw1 = ry + float(want_yaw[best])

func _springs(delta: float, head_pos: Vector3, sp_pos: Vector3) -> void:
	if delta <= 0.0:
		return
	var v := (head_pos - head_prev) / delta
	var acc := ((v - head_vprev) / delta).limit_length(40.0)
	head_prev = head_pos; head_vprev = v
	hat_vel += (Vector2(acc.z, -acc.x) * 0.012 - hat_ang * 160.0 - hat_vel * 10.0) * delta
	hat_ang = (hat_ang + hat_vel * delta).clamp(Vector2(-0.3, -0.3), Vector2(0.3, 0.3))
	var sv := (sp_pos - sp_prev) / delta
	var sa := ((sv - sp_vprev) / delta).limit_length(40.0)
	sp_prev = sp_pos; sp_vprev = sv
	# vest flaps swing back when the body accelerates forward, and bounce with the step
	vest_vel += ((sa.z * 0.5 + absf(sa.y) * 0.2) * 0.02 - vest_ang * 120.0 - vest_vel * 8.0) * delta
	vest_ang = clampf(vest_ang + vest_vel * delta, -0.25, 0.25)

func _set_expr(e: String) -> void:
	if e == expr:
		return
	expr = e
	var mouth := "sleep" if e == "relax" else e
	for m in ["smile", "grit", "laugh", "sleep", "oops"]:
		(parts["mouth_" + m] as Node3D).visible = m == mouth
	(parts["eyes"] as Node3D).visible = e != "sleep"
	(parts["eyes_closed"] as Node3D).visible = e == "sleep"

# ------------------------------------------------------------------ skeleton

static func _seg_basis(dir: Vector3, front: Vector3) -> Basis:
	var y := -dir.normalized()
	var z := -front
	z = (z - y * z.dot(y))
	if z.length_squared() < 1e-6:
		z = Vector3(0, 0, 1) - y * y.z
		if z.length_squared() < 1e-6:
			z = Vector3(1, 0, 0)
	z = z.normalized()
	var x := y.cross(z)
	return Basis(x, y, z)

static func _ik(a: Vector3, tgt: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var v := tgt - a
	var d := clampf(v.length(), 0.02, (l1 + l2) * 0.999)
	var dir := v.normalized() if v.length() > 1e-5 else Vector3.DOWN
	var ca := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 1e-6:
		bend = Vector3(0, 0, -1) - dir * dir.z
	bend = bend.normalized()
	var mid := a + dir * (l1 * ca) + bend * (l1 * sqrt(1.0 - ca * ca))
	var end := a + dir * d
	return [mid, end, bend]

## ankle position and foot basis for a foot planted at sole point fp (under the ankle).
## pitch > 0 rolls up onto the ball (heel lifts), pitch < 0 rocks back on the heel (toes lift).
static func _foot(fp: Vector3, yaw: float, pitch: float) -> Array:
	var yb := Basis(Vector3.UP, yaw)
	var piv := fp + yb * (Vector3(0, 0, -0.075) if pitch >= 0.0 else Vector3(0, 0, 0.06))
	var fb := yb * Basis(Vector3.RIGHT, -pitch)
	var a0 := fp + yb * Vector3(0, ANKLE_H, 0)
	return [piv + fb * (yb.inverse() * (a0 - piv)), fb]

func _skeleton(p: Dictionary, fp: Array, fy: Array, fpi: Array, reach: bool) -> Dictionary:
	var sk := {}
	var hop := float(p["hop"])
	var pb := Basis(Vector3.UP, float(p["pyaw"])) * Basis(Vector3.RIGHT, -float(p["plean"])) * Basis(Vector3.BACK, float(p["proll"]))
	var pel_o := Vector3(0, PEL_H + float(p["pdy"]) + hop, 0) + (p["poff"] as Vector3)
	var feet: Array = []
	for i in 2:
		feet.append(_foot((fp[i] as Vector3) + Vector3(0, hop, 0), float(fy[i]), float(fpi[i])))
	if reach:
		# never over-stretch a planted leg: lower the pelvis just enough (gives the walk its natural bob)
		var drop := 0.0
		for i in 2:
			var side := -1 if i == 0 else 1
			var hip := pel_o + pb * Vector3(HIP.x * side, HIP.y, HIP.z)
			var an: Vector3 = feet[i][0]
			var hz := Vector2(hip.x - an.x, hip.z - an.z).length()
			var vmax := sqrt(maxf(LEG_MAX * LEG_MAX - hz * hz, 0.01))
			drop = maxf(drop, ((hip.y - an.y) - vmax) * float(plant[i]))
		pel_o.y -= clampf(drop, 0.0, 0.2)
	var pel := Transform3D(pb, pel_o)
	sk["pelvis"] = pel
	var sb := Basis(Vector3.UP, float(p["sy"])) * Basis(Vector3.RIGHT, -float(p["sl"])) * Basis(Vector3.BACK, float(p["sr"]))
	var sp := pel * Transform3D(sb, Vector3(0, 0.04, 0))
	sk["spine"] = sp
	var hb := Basis(Vector3.UP, float(p["hy"])) * Basis(Vector3.RIGHT, -float(p["hd"])) * Basis(Vector3.BACK, float(p["hr"]))
	var hd := sp * Transform3D(hb, Vector3(0, 0.3, 0))
	sk["head"] = hd
	match hat_mode:
		"chest":
			sk["hat"] = sp * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + 0.15), Vector3(0, 0.15, -0.11))
		"ground":
			sk["hat"] = sp * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, 0.4), Vector3(0.47, 0.58, 0.07))
		_:
			var hatb := Basis(Vector3.RIGHT, 0.13 + hat_ang.x) * Basis(Vector3.BACK, hat_ang.y)
			sk["hat"] = hd * Transform3D(hatb, Vector3(0, 0.252, 0.012))
	# vest flaps pivot on the shoulder straps
	for side: int in [1, -1]:
		var piv := Vector3(0.075 * side, 0.28, -0.05)
		var fb := Basis(Vector3.RIGHT, vest_ang) * Basis(Vector3.FORWARD, vest_ang * 0.3 * side)
		sk["vest_" + ("r" if side == 1 else "l")] = sp * Transform3D(Basis.IDENTITY, piv) * Transform3D(fb, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -piv)
	for side: int in [1, -1]:
		var sh := sp * Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
		var key := "r" if side == 1 else "l"
		var tgt: Vector3 = sp * (p[key + "h"] as Vector3)
		var pole: Vector3 = sp.basis * (p[key + "e"] as Vector3)
		var r := _ik(sh, tgt, UARM, FARM, pole)
		var el: Vector3 = r[0]
		var wr: Vector3 = r[1]
		var front: Vector3 = -(r[2] as Vector3)
		var ub := _seg_basis(el - sh, front)
		var fb := _seg_basis(wr - el, front)
		sk["uarm_" + key] = Transform3D(ub, sh)
		sk["farm_" + key] = Transform3D(fb, el)
		var wrist := float(p["wr"]) if side == 1 else 0.1
		sk["hand_" + key] = Transform3D(fb * Basis(Vector3.RIGHT, wrist), wr)
	for i in 2:
		var side := -1 if i == 0 else 1
		var key := "l" if i == 0 else "r"
		var hip := pel * Vector3(HIP.x * side, HIP.y, HIP.z)
		var ankle: Vector3 = feet[i][0]
		var fb: Basis = feet[i][1]
		var ffwd := Basis(Vector3.UP, float(fy[i])) * Vector3(0, 0, -1)
		var pole := (pb * Vector3(0, -0.15, -1.0) + ffwd).normalized()
		var r := _ik(hip, ankle, THIGH, SHIN, pole)
		var kn: Vector3 = r[0]
		var an: Vector3 = r[1]
		var front: Vector3 = r[2]
		sk["thigh_" + key] = Transform3D(_seg_basis(kn - hip, front), hip)
		sk["shin_" + key] = Transform3D(_seg_basis(an - kn, front), kn)
		sk["foot_" + key] = Transform3D(fb, an)
	return sk

func _apply(sk: Dictionary, blink: float) -> void:
	for k in sk:
		if parts.has(k):
			(parts[k] as Node3D).transform = sk[k]
	var hd: Transform3D = sk["head"]
	for k in ["mouth_smile", "mouth_grit", "mouth_laugh", "mouth_sleep", "mouth_oops", "eyes_closed", "glasses"]:
		(parts[k] as Node3D).transform = hd
	(parts["eyes"] as Node3D).transform = hd * Transform3D(Basis.from_scale(Vector3(1, blink, 1)), eye_c)
	(parts["stone"] as Node3D).transform = (sk["hand_r"] as Transform3D) * Transform3D(Basis.IDENTITY, STONE_OFF)

## Freeze a named key pose (screenshots / tests). Returns the pelvis in boy space.
func debug_pose(kind: String, p := 1.0, tt := 0.3) -> Vector3:
	set_process(false)
	hat_mode = "head"
	(parts["glasses"] as Node3D).visible = false
	stance = "crouch" if kind.ends_with("_c") else "stand"
	var st := throw_stance()
	foot_p = [st[0][0], st[0][1]]
	foot_yaw = [st[1][0], st[1][1]]
	foot_pitch = [0.0, 0.0]
	var e := "smile"
	var fp_override := false
	match kind:
		"charge", "charge_c":
			cur = pose_charge(p); e = "grit"
		"release", "release_c":
			cur = pose_release(); e = "grit"
		"follow", "follow_c":
			cur = pose_follow(p); e = "grit" if kind == "follow_c" else "smile"
			if kind == "follow":
				var ss := settle_stance()
				foot_p = [ss[0][0], ss[0][1]]
				foot_yaw = [ss[1][0], ss[1][1]]
		"cheer":
			cur = pose_cheer(tt); e = "laugh"
			foot_p = [IDLE_L, IDLE_R]; foot_yaw = [0.08, -0.08]
		"oops":
			cur = pose_oops(tt); e = "oops"
			foot_p = [IDLE_L, IDLE_R]; foot_yaw = [0.08, -0.08]
		"walk", "run":
			return _debug_gait(1.1 if kind == "walk" else 2.7, tt)
		"sleep", "sun":
			cur = pose_lie_sleep(tt) if kind == "sleep" else pose_lie_sun(tt)
			hat_mode = "chest" if kind == "sleep" else "ground"
			(parts["glasses"] as Node3D).visible = kind == "sun"
			e = "sleep" if kind == "sleep" else "relax"
			fp_override = true
		"sit_edge", "sit_ground":
			cur = pose_sit_edge() if kind == "sit_edge" else pose_sit_ground()
			fp_override = true
		"grit":
			cur = pose_idle(); e = "grit"
			foot_p = [IDLE_L, IDLE_R]; foot_yaw = [0.08, -0.08]
		_:
			cur = pose_idle()
			foot_p = [IDLE_L, IDLE_R]; foot_yaw = [0.08, -0.08]
	if fp_override:
		foot_p = [cur["flp"], cur["frp"]]
		foot_yaw = [float(cur["fly"]), float(cur["fry"])]
	if kind.begins_with("release") or kind.begins_with("charge") or kind.begins_with("follow") or fp_override:
		foot_pitch = [float(cur["lheel"]), float(cur["rheel"])]
	plant = [1.0, 1.0]
	_set_expr(e)
	show_stone(kind in ["idle", "charge", "release", "charge_c", "release_c", "grit"])
	var sk := _skeleton(cur, foot_p, foot_yaw, foot_pitch, not fp_override)
	_apply(sk, 1.0)
	return (sk["pelvis"] as Transform3D).origin

## run the gait for a while along -Z, then freeze at cycle phase `ph` back at the origin
func _debug_gait(spd: float, ph: float) -> Vector3:
	var dt := 1.0 / 60.0
	position = Vector3.ZERO
	foot_p = [IDLE_L, IDLE_R]
	foot_yaw = [0.08, -0.08]
	reanchor = true
	anim = "idle"
	_tick(dt)
	vel_s = Vector3(0, 0, -spd)
	speed_s = spd
	move_speed = spd
	_start_gait()
	var n := 0
	while n < 600 and (n < 150 or absf(fposmod(gait_ph - ph + 0.5, 1.0) - 0.5) > 0.016):
		position.z -= spd * dt
		_tick(dt)
		n += 1
	var off := position
	position = Vector3.ZERO
	for i in 2:
		fw[i] -= off
	lift_w[0] -= off
	lift_w[1] -= off
	prev_root = Vector3.ZERO
	_to_local()
	var sk := _skeleton(cur, foot_p, foot_yaw, foot_pitch, true)
	_apply(sk, 1.0)
	return (sk["pelvis"] as Transform3D).origin
