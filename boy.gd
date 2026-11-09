class_name Boy
extends Node3D
## The stone-skipping kid: straw hat, red tank top, yellow board shorts, flip-flops.
## Low-poly parts driven by a small procedural skeleton (pelvis/spine/head, 2-bone IK arms and legs).
## Faces -Z, right hand = +X. Root sits on the deck at the feet.

signal released

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

const SKIN := Color(0.93, 0.71, 0.53)
const RED := Color(0.86, 0.12, 0.1)
const TRIM := Color(0.98, 0.96, 0.9)
const YEL := Color(1.0, 0.8, 0.12)
const YEL2 := Color(0.93, 0.62, 0.04)
const STRAW := Color(0.95, 0.85, 0.6)
const STRAW2 := Color(0.84, 0.69, 0.42)
const HAIR := Color(0.17, 0.1, 0.06)
const SOLE := Color(0.12, 0.5, 0.85)

var parts := {}
var mat: ShaderMaterial
var t := 0.0
var anim := "idle"   # idle | charge | throw | react
var anim_t := 0.0
var power := 0.0
var throw_power := 0.0
var react_kind := ""
var did_release := false
var cur := {}
var from_pose := {}
var release_local := Vector3.ZERO
var stone_visible := true

# feet: planted sole points (boy space), yaw, stepping
var foot_p: Array[Vector3] = [Vector3(-0.085, 0, -0.02), Vector3(0.085, 0, 0.02)]
var foot_yaw: Array[float] = [0.08, -0.08]
var step_i := -1
var step_t := 0.0
var step_from := Vector3.ZERO
var step_to := Vector3.ZERO
var step_yaw0 := 0.0
var step_yaw1 := 0.0

# idle look / blink / hat spring
var look_target := 0.0
var look_timer := 3.0
var blink_timer := 2.5
var hat_ang := Vector2.ZERO
var hat_vel := Vector2.ZERO
var head_prev := Vector3.ZERO
var head_vprev := Vector3.ZERO
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 7
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/character.gdshader")
	_build_parts()
	cur = pose_idle()
	var rp := pose_release()
	var sk := _skeleton(rp, [Vector3(-0.06, 0, -0.16), Vector3(0.17, 0, 0.13)], [-0.25, -0.7])
	release_local = (sk["hand_r"] as Transform3D) * STONE_OFF
	_apply(_skeleton(cur, foot_p, foot_yaw), 1.0)

# ------------------------------------------------------------------ public API

func set_idle() -> void:
	if anim == "charge":
		anim = "idle"
	elif anim != "throw" and anim != "react":
		anim = "idle"

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

func hand_stone_global() -> Vector3:
	return global_transform * ((parts["stone"] as MeshInstance3D).transform.origin)

# ------------------------------------------------------------------ poses

func pose_idle() -> Dictionary:
	return {
		"pdy": 0.0, "pyaw": 0.0, "plean": 0.03, "proll": 0.0, "poff": Vector3.ZERO,
		"sy": 0.0, "sl": 0.02, "sr": 0.0, "hy": 0.0, "hd": 0.0, "wr": 0.15,
		"rh": Vector3(0.165, -0.035, -0.055), "re": Vector3(0.3, 0.0, 1.0),
		"lh": Vector3(-0.16, -0.035, -0.03), "le": Vector3(-0.3, 0.0, 1.0),
		"rheel": 0.0, "lheel": 0.0, "rlift": 0.0, "rlt": Vector3(0.14, 0.1, 0.22), "rfp": 0.0,
	}

func pose_charge(p: float) -> Dictionary:
	var a := {
		"pdy": -0.045, "pyaw": -0.22, "plean": 0.1, "proll": -0.02, "poff": Vector3(0.015, 0, 0.02),
		"sy": -0.2, "sl": 0.12, "sr": -0.08, "hy": 0.36, "hd": 0.05, "wr": 0.4,
		"rh": Vector3(0.27, 0.0, 0.11), "re": Vector3(0.1, -0.7, 1.0),
		"lh": Vector3(-0.17, 0.06, -0.16), "le": Vector3(-0.6, -1.0, 0.2),
		"rheel": 0.0, "lheel": 0.0, "rlift": 0.0, "rlt": Vector3(0.14, 0.1, 0.22), "rfp": 0.0,
	}
	var b := {
		"pdy": -0.13, "pyaw": -0.48, "plean": 0.17, "proll": -0.06, "poff": Vector3(0.045, 0, 0.05),
		"sy": -0.46, "sl": 0.26, "sr": -0.22, "hy": 0.82, "hd": 0.08, "wr": 0.75,
		"rh": Vector3(0.34, 0.09, 0.13), "re": Vector3(0.0, -0.6, 1.0),
		"lh": Vector3(-0.18, 0.16, -0.24), "le": Vector3(-0.5, -1.0, 0.3),
		"rheel": 0.0, "lheel": 0.0, "rlift": 0.0, "rlt": Vector3(0.14, 0.1, 0.22), "rfp": 0.0,
	}
	return _mix(a, b, p)

func pose_release() -> Dictionary:
	return {
		"pdy": -0.095, "pyaw": 0.24, "plean": 0.2, "proll": 0.0, "poff": Vector3(-0.02, 0, -0.035),
		"sy": 0.22, "sl": 0.3, "sr": -0.16, "hy": -0.42, "hd": 0.1, "wr": -0.55,
		"rh": Vector3(0.3, 0.02, -0.13), "re": Vector3(0.3, -0.8, 0.6),
		"lh": Vector3(-0.26, 0.1, 0.03), "le": Vector3(-0.6, -1.0, 0.0),
		"rheel": 0.55, "lheel": 0.0, "rlift": 0.0, "rlt": Vector3(0.15, 0.06, 0.2), "rfp": -0.6,
	}

func pose_follow(p: float) -> Dictionary:
	return {
		"pdy": -0.075, "pyaw": 0.5, "plean": lerpf(0.22, 0.4, p), "proll": 0.04, "poff": Vector3(-0.04, 0, -0.08),
		"sy": 0.4, "sl": lerpf(0.25, 0.42, p), "sr": 0.05, "hy": -0.8, "hd": -0.12, "wr": -0.3,
		"rh": Vector3(-0.06, 0.08, -0.2), "re": Vector3(0.6, -1.0, 0.0),
		"lh": Vector3(-0.3, 0.16, 0.1), "le": Vector3(-0.3, -1.0, 0.5),
		"rheel": 0.0, "lheel": 0.0, "rlift": 1.0,
		"rlt": Vector3(0.14, 0.06, 0.2).lerp(Vector3(0.13, 0.41, 0.25), p), "rfp": -lerpf(0.8, 1.9, p),
	}

func pose_settle() -> Dictionary:
	return {
		"pdy": -0.02, "pyaw": 0.16, "plean": 0.12, "proll": 0.0, "poff": Vector3(0.0, 0, -0.03),
		"sy": 0.1, "sl": 0.12, "sr": 0.0, "hy": -0.26, "hd": -0.06, "wr": 0.1,
		"rh": Vector3(0.17, -0.02, -0.06), "re": Vector3(0.3, 0.0, 1.0),
		"lh": Vector3(-0.165, -0.02, -0.04), "le": Vector3(-0.3, 0.0, 1.0),
		"rheel": 0.0, "lheel": 0.0, "rlift": 0.0, "rlt": Vector3(0.14, 0.06, 0.2), "rfp": 0.0,
	}

func pose_cheer(tt: float) -> Dictionary:
	var bounce := absf(sin(tt * 9.0)) * 0.05
	var w := sin(tt * 18.0) * 0.05
	return {
		"pdy": -0.06 + bounce, "pyaw": 0.05, "plean": -0.04, "proll": 0.0, "poff": Vector3.ZERO,
		"sy": 0.0, "sl": -0.06, "sr": sin(tt * 9.0) * 0.05, "hy": 0.0, "hd": -0.25, "wr": 0.0,
		"rh": Vector3(0.31 + w, 0.54, -0.08), "re": Vector3(1.0, -0.3, 0.3),
		"lh": Vector3(-0.31 + w, 0.54, -0.08), "le": Vector3(-1.0, -0.3, 0.3),
		"rheel": 0.0, "lheel": 0.0, "rlift": 0.0, "rlt": Vector3(0.14, 0.06, 0.2), "rfp": 0.0,
	}

func pose_oops(tt: float) -> Dictionary:
	return {
		"pdy": -0.03, "pyaw": 0.0, "plean": 0.1, "proll": 0.0, "poff": Vector3.ZERO,
		"sy": 0.0, "sl": 0.1, "sr": 0.0, "hy": sin(tt * 7.0) * 0.18, "hd": 0.2, "wr": 0.0,
		"rh": Vector3(0.175, 0.44, 0.0), "re": Vector3(1.0, -0.4, 0.3),
		"lh": Vector3(-0.175, 0.44, 0.0), "le": Vector3(-1.0, -0.4, 0.3),
		"rheel": 0.0, "lheel": 0.0, "rlift": 0.0, "rlt": Vector3(0.14, 0.06, 0.2), "rfp": 0.0,
	}

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

# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	t += delta
	anim_t += delta
	var want: Dictionary
	var stance_l := Vector3(-0.085, 0, -0.02)
	var stance_r := Vector3(0.085, 0, 0.02)
	var yaw_l := 0.08
	var yaw_r := -0.08
	var direct := false
	match anim:
		"charge":
			want = pose_charge(power)
			stance_l = Vector3(-0.06, 0, -0.16); stance_r = Vector3(0.17, 0, 0.13)
			yaw_l = -0.25; yaw_r = -0.7
		"throw":
			stance_l = Vector3(-0.06, 0, -0.16); stance_r = Vector3(0.17, 0, 0.13)
			yaw_l = -0.25; yaw_r = -0.7
			direct = true
			var a := anim_t
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
			if a >= T_FOLLOW * 0.9:
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
			if anim_t > 2.8:
				anim = "idle"
		_:
			want = pose_idle()
			# breathing, light sway, occasionally gaze out to sea
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
	if direct:
		cur = want
	else:
		cur = _mix(cur, want, 1.0 - exp(-delta * (14.0 if anim == "charge" else 6.0)))
	_update_feet(delta, [stance_l, stance_r], [yaw_l, yaw_r], float(cur["rlift"]) > 0.5)
	var sk := _skeleton(cur, foot_p, foot_yaw)
	# blink
	blink_timer -= delta
	var blink := 1.0
	if blink_timer < 0.12:
		blink = 0.12
		if blink_timer < 0.0:
			blink_timer = rng.randf_range(2.0, 4.5)
	_hat_spring(delta, (sk["head"] as Transform3D).origin)
	_apply(sk, blink)

func _update_feet(delta: float, want_p: Array, want_yaw: Array, r_free: bool) -> void:
	if r_free:
		foot_p[1] = want_p[1]; foot_yaw[1] = want_yaw[1]   # foot is in the air: re-plant without sliding
		if step_i == 1:
			step_i = -1
	if step_i >= 0:
		step_t += delta / 0.22
		var k := smoothstep(0.0, 1.0, min(step_t, 1.0))
		var p := step_from.lerp(step_to, k)
		p.y = sin(PI * min(step_t, 1.0)) * 0.055
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
			step_from = Vector3(foot_p[i].x, 0, foot_p[i].z); step_to = tp
			step_yaw0 = foot_yaw[i]; step_yaw1 = want_yaw[i]
			return

func _hat_spring(delta: float, head_pos: Vector3) -> void:
	if delta <= 0.0:
		return
	var v := (head_pos - head_prev) / delta
	var acc := (v - head_vprev) / delta
	head_prev = head_pos; head_vprev = v
	acc = acc.limit_length(40.0)
	var force := Vector2(acc.z, -acc.x) * 0.012
	hat_vel += (force - hat_ang * 160.0 - hat_vel * 10.0) * delta
	hat_ang += hat_vel * delta
	hat_ang = hat_ang.clamp(Vector2(-0.3, -0.3), Vector2(0.3, 0.3))

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
	var hatb := Basis(Vector3.RIGHT, 0.13 + hat_ang.x) * Basis(Vector3.BACK, hat_ang.y)
	sk["hat"] = hd * Transform3D(hatb, Vector3(0, 0.218, 0.005))
	# arms (targets in spine space)
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
	# legs (feet planted in boy space)
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
	var c := Vector3(0, 0.158, -0.13)
	(parts["eyes"] as Node3D).transform = hd * Transform3D(Basis.from_scale(Vector3(1, blink, 1)), c)
	(parts["stone"] as Node3D).transform = (sk["hand_r"] as Transform3D) * Transform3D(Basis.IDENTITY, STONE_OFF)

# ------------------------------------------------------------------ meshes

func _part(name: String, b: MeshBuilder) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = b.commit()
	mi.material_override = mat
	add_child(mi)
	parts[name] = mi

static func _cyl(b: MeshBuilder, a: Vector3, c: Vector3, r0: float, r1: float, col: Color, seg := 10, zs := 1.0) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = r0; m.top_radius = r1; m.height = 1.0
	m.radial_segments = seg; m.rings = 1
	var d := c - a
	var y := d.normalized()
	var x := y.cross(Vector3(0, 0, 1))
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3(1, 0, 0))
	x = x.normalized()
	var z := x.cross(y).normalized()
	b.prim(m, Transform3D(Basis(x, y * d.length(), z * zs), (a + c) * 0.5), col)

static func _sph(b: MeshBuilder, c: Vector3, r: Vector3, col: Color, seg := 10, rings := 6, basis := Basis.IDENTITY) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0; m.height = 2.0; m.radial_segments = seg; m.rings = rings
	b.prim(m, Transform3D(basis * Basis.from_scale(r), c), col)

static func _box(b: MeshBuilder, c: Vector3, s: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var m := BoxMesh.new()
	b.prim(m, Transform3D(basis * Basis.from_scale(s), c), col)

## small flower printed on a surface point with outward normal n
static func _flower(b: MeshBuilder, p: Vector3, n: Vector3, s: float, petal: Color, centre: Color) -> void:
	var z := n.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x)
	var bs := Basis(x, y, z)
	for k in 5:
		var a := k * TAU / 5.0
		_sph(b, p + bs * Vector3(cos(a), sin(a), 0) * s * 0.9, Vector3(s * 0.75, s * 0.75, s * 0.25), petal, 6, 3, bs)
	_sph(b, p + z * s * 0.15, Vector3(s * 0.45, s * 0.45, s * 0.3), centre, 6, 3, bs)

func _build_parts() -> void:
	var b: MeshBuilder
	# ---- pelvis: board shorts waist
	b = MeshBuilder.new()
	_cyl(b, Vector3(0, -0.07, 0), Vector3(0, 0.07, 0), 0.13, 0.125, YEL, 12, 0.78)
	_cyl(b, Vector3(0, 0.05, 0), Vector3(0, 0.085, 0), 0.128, 0.127, YEL2, 12, 0.8)
	_sph(b, Vector3(0, -0.065, 0.005), Vector3(0.125, 0.06, 0.097), YEL, 12, 5)
	# drawstring
	for sx: int in [-1, 1]:
		_box(b, Vector3(0.012 * sx, 0.045, -0.104), Vector3(0.006, 0.04, 0.006), TRIM, Basis(Vector3.BACK, 0.12 * sx))
		_sph(b, Vector3(0.015 * sx, 0.024, -0.104), Vector3(0.007, 0.008, 0.007), TRIM, 6, 3)
	_sph(b, Vector3(0, 0.066, -0.104), Vector3(0.014, 0.01, 0.008), TRIM, 6, 3)
	for k in 7:
		var a := -2.6 + k * 0.85
		var y := -0.035 + (k % 2) * 0.05
		var n := Vector3(sin(a), 0, -cos(a) * 1.25)
		_flower(b, Vector3(sin(a) * 0.128, y, -cos(a) * 0.1), n, 0.014, Color(1, 0.98, 0.92), Color(1, 0.42, 0.08))
	_part("pelvis", b)
	# ---- spine: red tank top, shoulders, neck
	b = MeshBuilder.new()
	_cyl(b, Vector3(0, -0.02, 0), Vector3(0, 0.235, 0), 0.118, 0.126, RED, 12, 0.72)
	_cyl(b, Vector3(0, -0.02, 0), Vector3(0, 0.0, 0), 0.121, 0.121, TRIM, 12, 0.74)
	_cyl(b, Vector3(0, 0.225, 0), Vector3(0, 0.24, 0), 0.128, 0.127, TRIM, 12, 0.74)
	_cyl(b, Vector3(0, 0.235, 0), Vector3(0, 0.285, 0), 0.118, 0.07, SKIN, 12, 0.72)
	_cyl(b, Vector3(0, 0.26, 0), Vector3(0, 0.33, 0), 0.047, 0.044, SKIN, 8)
	for sx: int in [-1, 1]:
		_box(b, Vector3(0.062 * sx, 0.262, -0.0), Vector3(0.036, 0.016, 0.17), RED, Basis(Vector3.BACK, -0.62 * sx))
		_sph(b, Vector3(SHOULDER.x * sx, SHOULDER.y - 0.004, 0), Vector3(0.042, 0.042, 0.042), SKIN, 8, 5)
	# little white palm-wave logo on the chest
	_sph(b, Vector3(-0.045, 0.15, -0.09), Vector3(0.026, 0.02, 0.006), TRIM, 8, 3)
	_sph(b, Vector3(-0.045, 0.148, -0.093), Vector3(0.016, 0.009, 0.006), Color(0.2, 0.6, 0.9), 8, 3)
	_part("spine", b)
	# ---- head (origin at the neck top)
	b = MeshBuilder.new()
	_sph(b, Vector3(0, 0.15, 0), Vector3(0.15, 0.145, 0.145), SKIN, 16, 10)
	_sph(b, Vector3(0, 0.1, -0.018), Vector3(0.124, 0.1, 0.118), SKIN, 14, 8)
	for sx: int in [-1, 1]:
		_sph(b, Vector3(0.147 * sx, 0.13, 0.008), Vector3(0.022, 0.038, 0.024), SKIN.darkened(0.05), 8, 4)
		_sph(b, Vector3(0.086 * sx, 0.103, -0.112), Vector3(0.026, 0.015, 0.006), Color(1.0, 0.52, 0.5), 8, 3, Basis(Vector3.UP, -0.62 * sx))
		_box(b, Vector3(0.056 * sx, 0.203, -0.128), Vector3(0.036, 0.009, 0.01), HAIR, Basis(Vector3.UP, -0.38 * sx) * Basis(Vector3.BACK, 0.12 * sx))
	_sph(b, Vector3(0, 0.122, -0.147), Vector3(0.017, 0.014, 0.014), SKIN.darkened(0.08), 8, 4)
	# smile
	for k in 5:
		var u := (k - 2) / 2.0
		_box(b, Vector3(u * 0.018, 0.073 + u * u * 0.007, -0.13 + absf(u) * 0.006), Vector3(0.011, 0.006, 0.006), Color(0.55, 0.16, 0.12), Basis(Vector3.BACK, u * 0.5))
	# hair: back/sides under the hat + fringe
	_sph(b, Vector3(0, 0.168, 0.035), Vector3(0.153, 0.133, 0.135), HAIR, 14, 8)
	for k in 7:
		var a := -0.75 + k * 0.25
		var base := Vector3(sin(a) * 0.137, 0.215, -cos(a) * 0.128)
		_sph(b, base, Vector3(0.03, 0.03, 0.016), HAIR, 6, 3, Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 0.4 * signf(a)))
	for sx: int in [-1, 1]:
		_sph(b, Vector3(0.138 * sx, 0.165, -0.04), Vector3(0.018, 0.045, 0.03), HAIR, 6, 3)
	_part("head", b)
	# eyes (separate so they can blink)
	b = MeshBuilder.new()
	for sx: int in [-1, 1]:
		var eb := Basis(Vector3.UP, -0.38 * sx)
		_sph(b, Vector3(0.055 * sx, 0.0, 0.0), Vector3(0.019, 0.027, 0.01), Color(0.06, 0.04, 0.04), 8, 5, eb)
		_sph(b, Vector3(0.055 * sx + 0.007, 0.01, -0.009), Vector3(0.006, 0.006, 0.004), Color(1, 1, 1), 6, 3, eb)
	_part("eyes", b)
	# ---- straw hat (origin where it sits on the head)
	b = MeshBuilder.new()
	_cyl(b, Vector3(0, -0.005, 0), Vector3(0, 0.08, 0), 0.152, 0.13, STRAW, 16)
	_sph(b, Vector3(0, 0.08, 0), Vector3(0.13, 0.035, 0.13), STRAW, 16, 4)
	_cyl(b, Vector3(0, 0.0, 0), Vector3(0, 0.03, 0), 0.155, 0.151, Color(0.82, 0.14, 0.1), 16)
	_box(b, Vector3(0.13, 0.016, -0.08), Vector3(0.03, 0.04, 0.01), Color(0.82, 0.14, 0.1), Basis(Vector3.UP, 1.0))
	# woven crown stripes
	for k in 16:
		var a0 := k * TAU / 16.0
		var col := STRAW2 if k % 2 == 0 else STRAW.lightened(0.05)
		_box(b, Vector3(sin(a0) * 0.142, 0.055, cos(a0) * 0.142), Vector3(0.012, 0.03, 0.004), col, Basis(Vector3.UP, a0))
	# brim: woven checker ring with a gentle droop, double sided
	var seg := 32
	var rings := [0.145, 0.19, 0.235, 0.275]
	for ri in 3:
		for k in seg:
			var a0 := k * TAU / seg
			var a1 := (k + 1) * TAU / seg
			var r0: float = rings[ri]
			var r1: float = rings[ri + 1]
			var y0 := -0.03 * pow((r0 - 0.145) / 0.13, 2.0)
			var y1 := -0.03 * pow((r1 - 0.145) / 0.13, 2.0)
			var p00 := Vector3(sin(a0) * r0, y0, cos(a0) * r0)
			var p01 := Vector3(sin(a1) * r0, y0, cos(a1) * r0)
			var p10 := Vector3(sin(a0) * r1, y1, cos(a0) * r1)
			var p11 := Vector3(sin(a1) * r1, y1, cos(a1) * r1)
			var col := STRAW if (k + ri) % 2 == 0 else STRAW2
			if ri == 2 and k % 2 == 0:
				col = col.darkened(0.06)
			b.face(p00, p10, p11, col, col, col, Vector3.UP)
			b.face(p00, p11, p01, col, col, col, Vector3.UP)
			var d := Vector3(0, -0.009, 0)
			var cu := col.darkened(0.15)
			b.face(p00 + d, p10 + d, p11 + d, cu, cu, cu, Vector3.DOWN)
			b.face(p00 + d, p11 + d, p01 + d, cu, cu, cu, Vector3.DOWN)
			if ri == 2:
				b.face(p10, p10 + d, p11 + d, cu, cu, cu, Vector3(p10.x, 0, p10.z))
				b.face(p10, p11 + d, p11, cu, cu, cu, Vector3(p10.x, 0, p10.z))
	_part("hat", b)
	# ---- arms
	for key: String in ["r", "l"]:
		b = MeshBuilder.new()
		_cyl(b, Vector3(0, 0.0, 0), Vector3(0, -UARM, 0), 0.036, 0.031, SKIN, 8)
		_sph(b, Vector3(0, -UARM, 0), Vector3(0.031, 0.031, 0.031), SKIN, 8, 4)
		_part("uarm_" + key, b)
		b = MeshBuilder.new()
		_cyl(b, Vector3(0, 0.0, 0), Vector3(0, -FARM, 0), 0.031, 0.026, SKIN, 8)
		_part("farm_" + key, b)
		b = MeshBuilder.new()
		var sx := 1.0 if key == "r" else -1.0
		_sph(b, Vector3(0, -0.04, 0), Vector3(0.029, 0.042, 0.026), SKIN, 8, 5)
		_sph(b, Vector3(-0.022 * sx, -0.03, -0.014), Vector3(0.011, 0.024, 0.011), SKIN, 6, 3, Basis(Vector3.BACK, 0.5 * sx))
		_part("hand_" + key, b)
	# ---- legs
	for key: String in ["r", "l"]:
		b = MeshBuilder.new()
		_cyl(b, Vector3(0, 0.03, 0), Vector3(0, -0.135, 0), 0.07, 0.064, YEL, 10)
		_cyl(b, Vector3(0, -0.125, 0), Vector3(0, -0.142, 0), 0.066, 0.066, YEL2, 10)
		var sx := 1.0 if key == "r" else -1.0
		for k in 3:
			var a := (0.6 + k * 1.7) * sx
			_flower(b, Vector3(sin(a) * 0.068, -0.03 - k * 0.035, -cos(a) * 0.068), Vector3(sin(a), 0, -cos(a)), 0.013, Color(1, 0.98, 0.92), Color(1, 0.42, 0.08))
		_cyl(b, Vector3(0, -0.12, 0), Vector3(0, -THIGH, 0), 0.049, 0.043, SKIN, 8)
		_sph(b, Vector3(0, -THIGH, -0.004), Vector3(0.044, 0.044, 0.044), SKIN, 8, 4)
		_part("thigh_" + key, b)
		b = MeshBuilder.new()
		_cyl(b, Vector3(0, 0.0, 0), Vector3(0, -SHIN, 0), 0.042, 0.03, SKIN, 8)
		_sph(b, Vector3(0, -0.075, 0.01), Vector3(0.043, 0.07, 0.044), SKIN, 8, 5)
		_part("shin_" + key, b)
		b = MeshBuilder.new()
		_sph(b, Vector3(0, -0.005, 0), Vector3(0.03, 0.03, 0.03), SKIN, 8, 4)
		_sph(b, Vector3(0, -0.035, -0.035), Vector3(0.04, 0.026, 0.082), SKIN, 10, 5)
		for k in 4:
			_sph(b, Vector3((-0.024 + k * 0.016) * sx, -0.042, -0.107 + absf(k - 1.2) * 0.004), Vector3(0.009, 0.009, 0.011), SKIN, 6, 3)
		_box(b, Vector3(0, -ANKLE_H + 0.006, -0.03), Vector3(0.08, 0.012, 0.2), SOLE)
		_box(b, Vector3(0, -ANKLE_H - 0.0, -0.03), Vector3(0.082, 0.005, 0.202), Color(0.95, 0.95, 0.9))
		for s2: int in [-1, 1]:
			_box(b, Vector3(0.02 * s2, -0.04, -0.055), Vector3(0.008, 0.01, 0.065), Color(0.95, 0.25, 0.2), Basis(Vector3.UP, 0.55 * s2))
		_part("foot_" + key, b)
	# ---- the flat skipping stone in the right hand
	b = MeshBuilder.new()
	var srng := RandomNumberGenerator.new()
	srng.seed = 3
	var sm := SphereMesh.new()
	sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 9; sm.rings = 4
	b.prim(sm, Transform3D(Basis.from_scale(Vector3(0.05, 0.017, 0.04)), Vector3.ZERO), Color(0.5, 0.52, 0.55), srng, 0.12, 0.04)
	_part("stone", b)

## Freeze a named key pose (screenshots / tests).
func debug_pose(kind: String, p := 1.0, tt := 0.3) -> void:
	set_process(false)
	var throw_l := Vector3(-0.06, 0, -0.16)
	var throw_r := Vector3(0.17, 0, 0.13)
	foot_p = [throw_l, throw_r]
	foot_yaw = [-0.25, -0.7]
	match kind:
		"charge":
			cur = pose_charge(p)
		"release":
			cur = pose_release()
		"follow":
			cur = pose_follow(p)
		"cheer":
			cur = pose_cheer(tt)
		"oops":
			cur = pose_oops(tt)
		_:
			cur = pose_idle()
			foot_p = [Vector3(-0.085, 0, -0.02), Vector3(0.085, 0, 0.02)]
			foot_yaw = [0.08, -0.08]
	show_stone(kind == "idle" or kind == "charge" or kind == "release")
	_apply(_skeleton(cur, foot_p, foot_yaw), 1.0)
