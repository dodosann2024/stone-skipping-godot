class_name Boy
extends Node3D
## The straw-hat boy (v4). Procedural skeleton: pelvis / spine / head, 2-bone IK arms and legs.
## Animations: idle, standing or half-kneeling sidearm throw, walk / run gait, reactions,
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
const HIP := Vector3(0.07, -0.025, 0.0)
const STONE_OFF := Vector3(0.0, -0.075, -0.018)
const T_RELEASE := 0.1
const T_FOLLOW := 0.4
const T_HOLD := 0.95
const T_SETTLE := 1.6
const IDLE_L := Vector3(-0.085, 0, -0.02)
const IDLE_R := Vector3(0.085, 0, 0.02)

var parts := {}
var mat: ShaderMaterial
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
var gait_ph := 0.0
var gait_w := 0.0
var prev_u := [0.5, 0.0]
var wading := false

var foot_p: Array[Vector3] = [IDLE_L, IDLE_R]
var foot_yaw: Array[float] = [0.08, -0.08]
var step_i := -1
var step_t := 0.0
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
	BoyMesh.build(self)
	(parts["hat"] as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parts["glasses"] as Node3D).visible = false
	expr = ""
	cur = pose_idle()
	stance = "stand"
	release_stand = _release_point()
	stance = "crouch"
	release_crouch = _release_point()
	stance = "stand"
	_set_expr("smile")
	_apply(_skeleton(cur, foot_p, foot_yaw), 1.0)

func add_part(name: String, b: MeshBuilder) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = b.commit()
	mi.material_override = mat
	add_child(mi)
	parts[name] = mi

func _release_point() -> Vector3:
	var st := throw_stance()
	var sk := _skeleton(pose_release(), st[0], st[1])
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
		anim = "move"

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
	return [[Vector3(-0.06, 0, -0.16), Vector3(0.17, 0, 0.13)], [-0.25, -0.7]]

# ------------------------------------------------------------------ poses

static func P(d: Dictionary) -> Dictionary:
	var base := {
		"pdy": 0.0, "pyaw": 0.0, "plean": 0.03, "proll": 0.0, "poff": Vector3.ZERO,
		"sy": 0.0, "sl": 0.02, "sr": 0.0, "hy": 0.0, "hd": 0.0, "wr": 0.15,
		"rh": Vector3(0.165, -0.035, -0.055), "re": Vector3(0.3, 0.0, 1.0),
		"lh": Vector3(-0.16, -0.035, -0.03), "le": Vector3(-0.3, 0.0, 1.0),
		"rheel": 0.0, "lheel": 0.0, "rlift": 0.0, "rlt": Vector3(0.14, 0.1, 0.22), "rfp": 0.0,
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
	return _mix(P({"pdy": -0.045, "pyaw": -0.22, "plean": 0.1, "proll": -0.02, "poff": Vector3(0.015, 0, 0.02),
		"sy": -0.2, "sl": 0.12, "sr": -0.08, "hy": 0.36, "hd": 0.05, "wr": 0.4,
		"rh": Vector3(0.27, 0.0, 0.11), "re": Vector3(0.1, -0.7, 1.0), "lh": Vector3(-0.17, 0.06, -0.16), "le": Vector3(-0.6, -1.0, 0.2)}),
		P({"pdy": -0.13, "pyaw": -0.48, "plean": 0.17, "proll": -0.06, "poff": Vector3(0.045, 0, 0.05),
		"sy": -0.46, "sl": 0.26, "sr": -0.22, "hy": 0.82, "hd": 0.08, "wr": 0.75,
		"rh": Vector3(0.34, 0.09, 0.13), "re": Vector3(0.0, -0.6, 1.0), "lh": Vector3(-0.18, 0.16, -0.24), "le": Vector3(-0.5, -1.0, 0.3)}), p)

func pose_release() -> Dictionary:
	if stance == "crouch":
		return P({"pdy": -0.255, "pyaw": 0.22, "plean": 0.36, "poff": Vector3(-0.02, 0, -0.02),
			"sy": 0.22, "sl": 0.38, "sr": -0.2, "hy": -0.42, "hd": 0.12, "wr": -0.55,
			"rh": Vector3(0.3, -0.07, -0.14), "re": Vector3(0.3, -0.8, 0.6), "lh": Vector3(-0.27, 0.04, 0.04), "le": Vector3(-0.6, -1.0, 0.0), "rheel": 1.25})
	return P({"pdy": -0.095, "pyaw": 0.24, "plean": 0.2, "poff": Vector3(-0.02, 0, -0.035),
		"sy": 0.22, "sl": 0.3, "sr": -0.16, "hy": -0.42, "hd": 0.1, "wr": -0.55,
		"rh": Vector3(0.3, 0.02, -0.13), "re": Vector3(0.3, -0.8, 0.6), "lh": Vector3(-0.26, 0.1, 0.03), "le": Vector3(-0.6, -1.0, 0.0),
		"rheel": 0.55, "rlt": Vector3(0.15, 0.06, 0.2), "rfp": -0.6})

func pose_follow(p: float) -> Dictionary:
	if stance == "crouch":
		return P({"pdy": -0.24, "pyaw": 0.45, "plean": lerpf(0.36, 0.46, p), "proll": 0.03, "poff": Vector3(-0.03, 0, -0.06),
			"sy": 0.38, "sl": lerpf(0.34, 0.48, p), "sr": 0.05, "hy": -0.75, "hd": -0.1, "wr": -0.3,
			"rh": Vector3(-0.07, 0.02, -0.21), "re": Vector3(0.6, -1.0, 0.0), "lh": Vector3(-0.3, 0.12, 0.1), "le": Vector3(-0.3, -1.0, 0.5), "rheel": 1.25})
	return P({"pdy": -0.075, "pyaw": 0.5, "plean": lerpf(0.22, 0.4, p), "proll": 0.04, "poff": Vector3(-0.04, 0, -0.08),
		"sy": 0.4, "sl": lerpf(0.25, 0.42, p), "sr": 0.05, "hy": -0.8, "hd": -0.12, "wr": -0.3,
		"rh": Vector3(-0.06, 0.08, -0.2), "re": Vector3(0.6, -1.0, 0.0), "lh": Vector3(-0.3, 0.16, 0.1), "le": Vector3(-0.3, -1.0, 0.5),
		"rlift": 1.0, "rlt": Vector3(0.14, 0.06, 0.2).lerp(Vector3(0.13, 0.41, 0.25), p), "rfp": -lerpf(0.8, 1.9, p)})

func pose_settle() -> Dictionary:
	if stance == "crouch":
		return P({"pdy": -0.2, "pyaw": 0.15, "plean": 0.25, "sy": 0.1, "sl": 0.15, "hy": -0.25, "hd": -0.05,
			"rh": Vector3(0.17, -0.05, -0.08), "lh": Vector3(-0.17, -0.04, -0.06), "rheel": 1.2})
	return P({"pdy": -0.02, "pyaw": 0.16, "plean": 0.12, "poff": Vector3(0.0, 0, -0.03), "sy": 0.1, "sl": 0.12, "hy": -0.26, "hd": -0.06, "wr": 0.1,
		"rh": Vector3(0.17, -0.02, -0.06), "lh": Vector3(-0.165, -0.02, -0.04)})

func pose_cheer(tt: float) -> Dictionary:
	var bounce := absf(sin(tt * 9.0)) * 0.05
	var w := sin(tt * 18.0) * 0.05
	return P({"pdy": -0.06 + bounce, "pyaw": 0.05, "plean": -0.04, "sl": -0.06, "sr": sin(tt * 9.0) * 0.05, "hd": -0.25, "wr": 0.0,
		"rh": Vector3(0.31 + w, 0.54, -0.08), "re": Vector3(1.0, -0.3, 0.3), "lh": Vector3(-0.31 + w, 0.54, -0.08), "le": Vector3(-1.0, -0.3, 0.3)})

func pose_oops(tt: float) -> Dictionary:
	return P({"pdy": -0.03, "plean": 0.1, "sl": 0.1, "hy": sin(tt * 7.0) * 0.18, "hd": 0.2, "wr": 0.0,
		"rh": Vector3(0.175, 0.44, 0.0), "re": Vector3(1.0, -0.4, 0.3), "lh": Vector3(-0.175, 0.44, 0.0), "le": Vector3(-1.0, -0.4, 0.3)})

## walk / run cycle. Also places the feet (stance foot slides back at exactly the ground speed).
func pose_gait(dt: float) -> Dictionary:
	var rk := smoothstep(1.3, 2.3, move_speed)
	var T := lerpf(0.66, 0.5, rk)
	var duty := lerpf(0.6, 0.36, rk)
	gait_ph = fposmod(gait_ph + dt / T, 1.0)
	var L := minf(move_speed * duty * T, 0.5)
	var lift := lerpf(0.05, 0.11, rk) * (0.6 if wading else 1.0)
	for i in 2:
		var u := fposmod(gait_ph + (0.0 if i == 0 else 0.5), 1.0)
		var x := -0.072 if i == 0 else 0.072
		var p: Vector3
		var heel := 0.0
		if u < duty:
			var s := u / duty
			p = Vector3(x, 0, lerpf(-L * 0.5, L * 0.5, s))
			heel = smoothstep(0.65, 1.0, s) * lerpf(0.35, 0.6, rk)
		else:
			var s := (u - duty) / (1.0 - duty)
			p = Vector3(x, sin(PI * s) * lift, lerpf(L * 0.5, -L * 0.5, smoothstep(0.0, 1.0, s)))
			heel = (1.0 - s) * 0.45 - smoothstep(0.7, 1.0, s) * 0.15
		foot_p[i] = foot_p[i].lerp(p, gait_w)
		foot_yaw[i] = lerpf(foot_yaw[i], 0.04 if i == 0 else -0.04, gait_w)
		if float(prev_u[i]) > u and gait_w > 0.5:
			footstep.emit(i, rk > 0.5)
		prev_u[i] = u
		if i == 0:
			cur_heel_l = heel
		else:
			cur_heel_r = heel
	var c := cos(TAU * gait_ph)
	var bob := lerpf(0.012, 0.03, rk) * cos(4.0 * PI * (gait_ph - duty * 0.5))
	var hy := 0.08 * sin(TAU * gait_ph)
	var aw := lerpf(0.09, 0.13, rk)
	var walk_r := Vector3(0.155, -0.02 + 0.015 * maxf(-c, 0.0), aw * -c)
	var walk_l := Vector3(-0.155, -0.02 + 0.015 * maxf(c, 0.0), aw * c)
	var run_r := Vector3(0.15, 0.1 + 0.04 * maxf(-c, 0.0), -0.06 - 0.13 * c)
	var run_l := Vector3(-0.15, 0.1 + 0.04 * maxf(c, 0.0), -0.06 + 0.13 * c)
	return P({"pdy": lerpf(-0.045, -0.075, rk) + bob, "pyaw": hy, "plean": lerpf(0.06, 0.2, rk), "proll": 0.02 * sin(TAU * gait_ph),
		"sy": -hy * 1.4, "sl": lerpf(0.03, 0.12, rk), "hy": hy * 0.4, "hd": lerpf(0.0, -0.08, rk), "wr": 0.2,
		"rh": walk_r.lerp(run_r, rk), "re": Vector3(0.3, -0.3 * rk, 1.0), "lh": walk_l.lerp(run_l, rk), "le": Vector3(-0.3, -0.3 * rk, 1.0),
		"rheel": cur_heel_r * gait_w, "lheel": cur_heel_l * gait_w})

var cur_heel_l := 0.0
var cur_heel_r := 0.0

# lying / sitting poses (boy space; main.gd rotates the root)
func pose_sit_edge() -> Dictionary:
	return P({"pdy": -0.2, "plean": 0.12, "sl": 0.08, "hd": 0.05,
		"rh": Vector3(0.2, -0.12, 0.04), "re": Vector3(0.4, 0, 1), "lh": Vector3(-0.2, -0.12, 0.04), "le": Vector3(-0.4, 0, 1),
		"flp": Vector3(-0.09, 0.0, -0.24), "frp": Vector3(0.09, 0.02, -0.22), "fly": 0.1, "fry": -0.1})

func pose_sit_ground() -> Dictionary:
	return P({"pdy": -0.45, "plean": -0.1, "sl": 0.15, "hd": 0.08,
		"rh": Vector3(0.2, -0.18, 0.14), "re": Vector3(0.3, 0, -1), "lh": Vector3(-0.2, -0.18, 0.14), "le": Vector3(-0.3, 0, -1),
		"flp": Vector3(-0.085, -0.02, -0.4), "frp": Vector3(0.085, -0.02, -0.42), "fly": 0.1, "fry": -0.1, "lheel": -1.2, "rheel": -1.2})

func pose_lie_sleep(tt: float) -> Dictionary:
	var br := sin(tt * 1.6) * 0.02
	return P({"pdy": -0.03, "plean": 0.2, "sl": 0.12 + br, "hd": -0.15,
		"rh": Vector3(0.06, 0.08, -0.13), "re": Vector3(1, 0, 0), "lh": Vector3(-0.07, 0.11, -0.12), "le": Vector3(-1, 0, 0),
		"flp": Vector3(-0.07, 0.03, -0.12), "frp": Vector3(0.08, 0.05, -0.1), "fly": 0.25, "fry": -0.25})

func pose_lie_sun(tt: float) -> Dictionary:
	var br := sin(tt * 1.3) * 0.015
	var tap := maxf(sin(tt * 2.2), 0.0) * 0.06
	return P({"pdy": -0.01, "plean": 0.02, "sl": 0.03 + br, "hd": -0.2,
		"rh": Vector3(0.085, 0.47, 0.11), "re": Vector3(1.0, 0.3, -0.2), "lh": Vector3(-0.085, 0.47, 0.11), "le": Vector3(-1.0, 0.3, -0.2),
		"flp": Vector3(-0.045, 0.0, -0.01), "frp": Vector3(-0.03, 0.03, -0.08 - tap), "fly": 0.15, "fry": 0.3})

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

static func _ease_in(x: float) -> float:
	return x * x

static func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)

# ------------------------------------------------------------------ activity (driven by main.gd)

## kind: "sleep" | "sun"; sit_k: 0 stand -> 1 seated; lie_k: 0 seated -> 1 lying. Returns the pelvis in boy space.
func activity(kind: String, sit_k: float, lie_k: float, tt: float) -> Vector3:
	anim = "activity"
	var sit := pose_sit_edge() if kind == "sleep" else pose_sit_ground()
	var lie := pose_lie_sleep(tt) if kind == "sleep" else pose_lie_sun(tt)
	var stand := P({"flp": foot_p[0], "frp": foot_p[1], "fly": foot_yaw[0], "fry": foot_yaw[1]})
	if sit_k <= 0.0 and lie_k <= 0.0:
		cur = stand
	cur = _mix(_mix(stand, sit, smoothstep(0.0, 1.0, sit_k)), lie, smoothstep(0.0, 1.0, lie_k))
	hat_mode = "head"
	if lie_k > 0.6:
		hat_mode = "chest" if kind == "sleep" else "ground"
	(parts["glasses"] as Node3D).visible = kind == "sun" and lie_k > 0.5
	if kind == "sleep":
		_set_expr("sleep" if lie_k > 0.7 else "smile")
	else:
		_set_expr("relax" if lie_k > 0.5 else "smile")
	show_stone(false)
	var fp: Array = [cur["flp"], cur["frp"]]
	var fy: Array = [float(cur["fly"]), float(cur["fry"])]
	var sk := _skeleton(cur, fp, fy)
	_apply(sk, 1.0)
	return (sk["pelvis"] as Transform3D).origin

func end_activity() -> void:
	anim = "idle"
	hat_mode = "head"
	(parts["glasses"] as Node3D).visible = false
	foot_p = [IDLE_L, IDLE_R]
	foot_yaw = [0.08, -0.08]
	cur = pose_idle()

# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	t += delta
	anim_t += delta
	if anim == "activity":
		return
	var want: Dictionary
	var stance_l := IDLE_L
	var stance_r := IDLE_R
	var yaw_l := 0.08
	var yaw_r := -0.08
	var direct := false
	var e := "smile"
	var gait := false
	match anim:
		"charge":
			want = pose_charge(power)
			var st := throw_stance()
			stance_l = st[0][0]; stance_r = st[0][1]; yaw_l = st[1][0]; yaw_r = st[1][1]
			e = "grit" if power > 0.35 else "smile"
		"throw":
			var st := throw_stance()
			stance_l = st[0][0]; stance_r = st[0][1]; yaw_l = st[1][0]; yaw_r = st[1][1]
			direct = true
			var a := anim_t
			e = "grit" if a < T_FOLLOW else "smile"
			if a < T_RELEASE:
				want = _mix(from_pose, pose_release(), _ease_in(a / T_RELEASE))
			elif a < T_FOLLOW:
				want = _mix(pose_release(), pose_follow(throw_power), _ease_out((a - T_RELEASE) / (T_FOLLOW - T_RELEASE)))
			elif a < T_HOLD:
				var f := pose_follow(throw_power)
				var h := (a - T_FOLLOW) / (T_HOLD - T_FOLLOW)
				f["rlt"] = (f["rlt"] as Vector3) + Vector3(0, -0.04 * h, 0)
				f["plean"] = float(f["plean"]) - 0.04 * h
				want = f
			elif a < T_SETTLE:
				want = _mix(pose_follow(throw_power), pose_settle(), smoothstep(0.0, 1.0, (a - T_HOLD) / (T_SETTLE - T_HOLD)))
			else:
				want = pose_settle()
			if a >= T_FOLLOW * 0.9 and stance == "stand":
				stance_r = Vector3(0.11, 0, 0.07); yaw_r = -0.4
			if not did_release and a >= T_RELEASE:
				did_release = true
				show_stone(false)
				released.emit()
		"react":
			stance_l = foot_p[0]; stance_r = foot_p[1]
			yaw_l = foot_yaw[0]; yaw_r = foot_yaw[1]
			var rp := pose_cheer(anim_t) if react_kind == "cheer" else pose_oops(anim_t)
			var k := smoothstep(0.0, 0.3, anim_t) * (1.0 - smoothstep(2.3, 2.8, anim_t))
			var base := _mix(from_pose, pose_settle(), smoothstep(0.0, 0.35, anim_t))
			want = _mix(base, rp, k)
			e = ("laugh" if react_kind == "cheer" else "oops") if k > 0.4 else "smile"
			if anim_t > 2.8:
				anim = "idle"
		"move":
			gait_w = minf(gait_w + delta * 5.0, 1.0)
			want = pose_gait(delta)
			gait = true
			if move_speed > 2.0:
				e = "laugh"
			if move_speed < 0.05:
				anim = "idle"
		_:
			want = pose_idle()
			want["sl"] = float(want["sl"]) + sin(t * 2.1) * 0.018
			want["pdy"] = float(want["pdy"]) + sin(t * 2.1) * 0.004
			want["poff"] = Vector3(sin(t * 0.7) * 0.012, 0, 0)
			want["proll"] = sin(t * 0.7) * 0.025
			look_timer -= delta
			if look_timer < 0.0:
				look_timer = rng.randf_range(2.5, 5.5)
				look_target = [0.0, 0.55, -0.5, 0.0, 0.25][rng.randi() % 5]
			want["hy"] = look_target
			want["hd"] = -0.08 if absf(look_target) > 0.1 else 0.0
			if not stone_visible:
				show_stone(true)
	if not gait:
		gait_w = 0.0
	if direct:
		cur = want
	else:
		cur = _mix(cur, want, 1.0 - exp(-delta * (14.0 if anim == "charge" or anim == "move" else 6.0)))
	if not gait:
		_update_feet(delta, [stance_l, stance_r], [yaw_l, yaw_r], float(cur["rlift"]) > 0.5)
	_set_expr(e)
	var sk := _skeleton(cur, foot_p, foot_yaw)
	blink_timer -= delta
	var blink := 1.0
	if blink_timer < 0.12:
		blink = 0.12
		if blink_timer < 0.0:
			blink_timer = rng.randf_range(2.0, 4.5)
	_springs(delta, (sk["head"] as Transform3D).origin, (sk["spine"] as Transform3D).origin)
	_apply(sk, blink)

func _update_feet(delta: float, want_p: Array, want_yaw: Array, r_free: bool) -> void:
	if r_free:
		foot_p[1] = want_p[1]; foot_yaw[1] = want_yaw[1]
		if step_i == 1:
			step_i = -1
	if step_i >= 0:
		step_t += delta / 0.22
		var k := smoothstep(0.0, 1.0, min(step_t, 1.0))
		var p := step_from.lerp(step_to, k)
		p.y = maxf(sin(PI * min(step_t, 1.0)) * 0.055, step_from.y * (1.0 - k))
		foot_p[step_i] = p
		foot_yaw[step_i] = lerpf(step_yaw0, step_yaw1, k)
		if step_t >= 1.0:
			foot_p[step_i] = step_to
			step_i = -1
		return
	for i: int in [1, 0]:
		if r_free and i == 1:
			continue
		var tp: Vector3 = want_p[i]
		if foot_p[i].distance_to(tp) > 0.012 or absf(foot_yaw[i] - float(want_yaw[i])) > 0.05:
			step_i = i; step_t = 0.0
			step_from = foot_p[i]; step_to = tp
			step_yaw0 = foot_yaw[i]; step_yaw1 = want_yaw[i]
			return

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

func _skeleton(p: Dictionary, fp: Array, fy: Array) -> Dictionary:
	var sk := {}
	var pb := Basis(Vector3.UP, float(p["pyaw"])) * Basis(Vector3.RIGHT, -float(p["plean"])) * Basis(Vector3.BACK, float(p["proll"]))
	var pel := Transform3D(pb, Vector3(0, PEL_H + float(p["pdy"]), 0) + (p["poff"] as Vector3))
	sk["pelvis"] = pel
	var sb := Basis(Vector3.UP, float(p["sy"])) * Basis(Vector3.RIGHT, -float(p["sl"])) * Basis(Vector3.BACK, float(p["sr"]))
	var sp := pel * Transform3D(sb, Vector3(0, 0.04, 0))
	sk["spine"] = sp
	var hb := Basis(Vector3.UP, float(p["hy"])) * Basis(Vector3.RIGHT, -float(p["hd"]))
	var hd := sp * Transform3D(hb, Vector3(0, 0.305, 0))
	sk["head"] = hd
	match hat_mode:
		"chest":
			sk["hat"] = sp * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + 0.15), Vector3(0, 0.14, -0.1))
		"ground":
			sk["hat"] = sp * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, 0.4), Vector3(0.43, 0.56, 0.07))
		_:
			var hatb := Basis(Vector3.RIGHT, 0.13 + hat_ang.x) * Basis(Vector3.BACK, hat_ang.y)
			sk["hat"] = hd * Transform3D(hatb, Vector3(0, 0.218, 0.005))
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
		var yb := Basis(Vector3.UP, float(fy[i]))
		var heel := float(p["rheel"]) if i == 1 else float(p["lheel"])
		var sole: Vector3 = fp[i]
		var ball := sole + yb * Vector3(0, 0, -0.075)
		var fb := yb * Basis(Vector3.RIGHT, -heel)
		var ankle := ball + fb * Vector3(0, ANKLE_H, 0.075)
		var lift := float(p["rlift"]) if i == 1 else 0.0
		var pole := pb * Vector3(0, -0.15, -1.0)
		if lift > 0.0:
			var lt := (p["rlt"] as Vector3) + Vector3(0, ANKLE_H, 0)
			ankle = ankle.lerp(lt, lift)
			pole = pole.lerp(pb * Vector3(0, -1.0, -0.35), lift)
			fb = yb * Basis(Vector3.RIGHT, lerpf(-heel, float(p["rfp"]), lift))
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
	var c := Vector3(0, 0.158, -0.13)
	(parts["eyes"] as Node3D).transform = hd * Transform3D(Basis.from_scale(Vector3(1, blink, 1)), c)
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
	var e := "smile"
	var fp_override := false
	match kind:
		"charge", "charge_c":
			cur = pose_charge(p); e = "grit"
		"release", "release_c":
			cur = pose_release(); e = "grit"
		"follow", "follow_c":
			cur = pose_follow(p); e = "grit" if kind == "follow_c" else "smile"
		"cheer":
			cur = pose_cheer(tt); e = "laugh"
		"oops":
			cur = pose_oops(tt); e = "oops"
		"walk", "run":
			move_speed = 1.1 if kind == "walk" else 2.7
			gait_w = 1.0
			gait_ph = tt
			cur = pose_gait(0.0)
			e = "laugh" if kind == "run" else "smile"
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
	_set_expr(e)
	show_stone(kind in ["idle", "charge", "release", "charge_c", "release_c", "grit"])
	var sk := _skeleton(cur, foot_p, foot_yaw)
	_apply(sk, 1.0)
	return (sk["pelvis"] as Transform3D).origin
