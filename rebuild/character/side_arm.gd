class_name SideArm
extends SkeletonModifier3D
## Side-arm skip throw on the approved skeleton.
## The library's pitch_baseball clip is an overhand pitch, so it is not used.

signal released(origin: Vector3, velocity: Vector3)
signal finished

var playing := false
var crouch := false
var hold := false
var phase := 0.0
var _fired := false
var _bi: Array[int] = []


func start(is_crouch: bool) -> void:
	crouch = is_crouch
	playing = true
	phase = 0.0
	_fired = false


func _process_modification_with_delta(delta: float) -> void:
	if not playing:
		return
	var skel := get_skeleton()
	if skel == null:
		return
	if delta <= 0.0:
		delta = 1.0 / 60.0
	_bind(skel)
	if _bi[0] < 0:
		playing = false
		return
	if not hold:
		phase += delta
	var dur := 1.15
	var u := clampf(phase / dur, 0.0, 1.0)
	# 0 coil, 1 deep load, then the whip and the follow-through.
	var s := clampf((phase - 0.02) / 0.95, 0.0, 1.0)
	var fwd := -skel.global_transform.basis.z
	fwd.y = 0.0
	fwd = Vector3(0, 0, -1) if fwd.length_squared() < 1e-6 else fwd.normalized()
	var right := skel.global_transform.basis.x
	right.y = 0.0
	right = Vector3(1, 0, 0) if right.length_squared() < 1e-6 else right.normalized()
	var load := smoothstep(0.0, 0.42, s)
	var drive := smoothstep(0.28, 0.72, s)
	var recover := smoothstep(0.78, 1.0, s)
	if _bi[6] >= 0:
		var hp := skel.get_bone_pose(_bi[6])
		# Deep crouch in the load, easing back up on the follow-through.
		# Pose units are pre-scale. FootIK plants both soles after this.
		var drop_m := lerpf(0.12, 0.26, load) * (1.0 - recover * 0.55)
		if crouch:
			drop_m += 0.04
		hp.origin.y -= drop_m / Constants.MODEL_SCALE
		# A few centimetres of weight shift. Hips turn first and stop;
		# the chest, below, keeps going past them.
		var shift := lerpf(0.035, -0.02, drive)
		hp.origin.x += shift / Constants.MODEL_SCALE
		var hip_yaw := lerpf(-0.42, 0.48, smoothstep(0.05, 0.5, s))
		hp.basis = hp.basis * Basis(Vector3.UP, -hip_yaw)
		skel.set_bone_pose(_bi[6], hp)
		var spine := _bone(skel, ["mixamorig_Spine", "mixamorig:Spine"])
		if spine >= 0:
			var sp := skel.get_bone_pose(spine)
			# Hips stay put. The chest turns from a coil into the follow-through,
			# and leans forward over the front knee.
			var yaw := lerpf(-0.85, 1.05, smoothstep(0.12, 0.92, s))
			var lean := sin(clampf(s * 1.2, 0.0, 1.0) * PI) * 0.32
			sp.basis = sp.basis * Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, lean)
			skel.set_bone_pose(spine, sp)
		var spine2 := _bone(skel, ["mixamorig_Spine2", "mixamorig:Spine2"])
		if spine2 >= 0:
			var s2 := skel.get_bone_pose(spine2)
			var late := lerpf(-0.35, 0.7, smoothstep(0.28, 1.0, s))
			s2.basis = s2.basis * Basis(Vector3.UP, -late)
			skel.set_bone_pose(spine2, s2)
		skel.force_update_all_bone_transforms()
	var shoulder := _world(skel, _bi[0])
	var deck_y := skel.global_position.y
	var knee_y := deck_y + 0.42
	# Behind the hip, then straight out at knee height, then across the body.
	var cocked := shoulder - fwd * 0.34 - right * 0.08 + Vector3.DOWN * 0.22
	var side_low := Vector3(shoulder.x, knee_y, shoulder.z) + right * 0.55 - fwd * 0.05
	var across := shoulder + fwd * 0.42 - right * 0.28 + Vector3.DOWN * 0.08
	var whip := smoothstep(0.18, 0.62, s)
	var hand := cocked.lerp(side_low, whip)
	if s >= 0.55:
		hand = side_low.lerp(across, smoothstep(0.55, 0.95, s))
	var pole := right * 1.2 + Vector3.DOWN * 0.85
	_solve(skel, _bi[0], _bi[1], _bi[2], hand, pole)
	var snap := smoothstep(0.40, 0.62, s) * (1.0 - smoothstep(0.78, 1.0, s))
	if _bi[2] >= 0 and snap > 0.01:
		var hb := skel.get_bone_pose(_bi[2])
		hb.basis = hb.basis * Basis(Vector3.RIGHT, -snap * 1.35)
		skel.set_bone_pose(_bi[2], hb)
	if s < 0.52:
		_curl_fingers(skel, 1.0)
	else:
		_curl_fingers(skel, clampf(1.0 - (s - 0.52) / 0.12, 0.0, 1.0))
	var lsh := _world(skel, _bi[3])
	var aim := lsh - fwd * 0.2 - right * 0.15 + Vector3.DOWN * 0.05
	if s > 0.45:
		aim = lsh + fwd * 0.15 + Vector3.DOWN * 0.28
	_solve(skel, _bi[3], _bi[4], _bi[5], aim, -right + Vector3.DOWN * 0.4)
	if not hold and not _fired and phase >= 0.52:
		_fired = true
		var origin := _world(skel, _bi[2])
		var grip := skel.get_node_or_null("PebbleGrip")
		if grip != null:
			origin = grip.global_position
		var speed := 10.4 if crouch else 11.2
		var lift := 0.35 if crouch else 0.45
		emit_signal("released", origin, fwd * speed + Vector3.UP * lift)
	if u >= 1.0:
		playing = false
		emit_signal("finished")


func _curl_fingers(skel: Skeleton3D, amount: float) -> void:
	if amount < 0.02:
		return
	var digits := ["Index", "Middle", "Ring", "Pinky"]
	for digit in digits:
		_bend(skel, "mixamorig_RightHand%s1" % digit, 0.85 * amount)
		_bend(skel, "mixamorig_RightHand%s2" % digit, 1.05 * amount)
		_bend(skel, "mixamorig_RightHand%s3" % digit, 0.75 * amount)
	_bend(skel, "mixamorig_RightHandThumb1", -0.7 * amount)
	_bend(skel, "mixamorig_RightHandThumb2", -0.9 * amount)
	_bend(skel, "mixamorig_RightHandThumb3", -0.6 * amount)


func _bend(skel: Skeleton3D, bone_name: String, ang: float) -> void:
	var i := skel.find_bone(bone_name)
	if i < 0:
		return
	var pose := skel.get_bone_pose(i)
	pose.basis = pose.basis * Basis(Vector3.RIGHT, ang)
	skel.set_bone_pose(i, pose)


func _bind(skel: Skeleton3D) -> void:
	if _bi.size() == 7:
		return
	_bi = [
		_bone(skel, ["mixamorig_RightArm", "mixamorig:RightArm"]),
		_bone(skel, ["mixamorig_RightForeArm", "mixamorig:RightForeArm"]),
		_bone(skel, ["mixamorig_RightHand", "mixamorig:RightHand"]),
		_bone(skel, ["mixamorig_LeftArm", "mixamorig:LeftArm"]),
		_bone(skel, ["mixamorig_LeftForeArm", "mixamorig:LeftForeArm"]),
		_bone(skel, ["mixamorig_LeftHand", "mixamorig:LeftHand"]),
		_bone(skel, ["mixamorig_Hips", "mixamorig:Hips"]),
	]


func _bone(skel: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := skel.find_bone(n)
		if i >= 0:
			return i
	return -1


func _solve(skel: Skeleton3D, up_i: int, mid_i: int, end_i: int, goal: Vector3, pole_hint: Vector3) -> void:
	if up_i < 0 or mid_i < 0 or end_i < 0:
		return
	var hip := _world(skel, up_i)
	var mid := _world(skel, mid_i)
	var tip := _world(skel, end_i)
	var len1 := hip.distance_to(mid)
	var len2 := mid.distance_to(tip)
	if len1 < 0.01 or len2 < 0.01:
		return
	var to_t := goal - hip
	if to_t.length_squared() < 1e-8:
		return
	var dist := clampf(to_t.length(), absf(len1 - len2) + 0.001, len1 + len2 - 0.001)
	var dir := to_t.normalized()
	var pole := pole_hint
	if pole.length_squared() < 1e-6:
		pole = Vector3.UP
	var ax := dir.cross(pole)
	if ax.length_squared() < 1e-8:
		ax = dir.cross(Vector3.UP)
	ax = ax.normalized()
	var cos_a := clampf((len1 * len1 + dist * dist - len2 * len2) / (2.0 * len1 * dist), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var side_v := ax.cross(dir).normalized()
	var elbow := hip + dir * (len1 * cos_a) + side_v * (len1 * sin_a)
	_aim(skel, up_i, mid_i, elbow)
	skel.force_update_all_bone_transforms()
	var nk := _world(skel, mid_i)
	var to_a := goal - nk
	if to_a.length_squared() < 1e-8:
		return
	_aim(skel, mid_i, end_i, nk + to_a.normalized() * len2)
	skel.force_update_all_bone_transforms()


func _aim(skel: Skeleton3D, parent_i: int, child_i: int, world_target: Vector3) -> void:
	var parent := skel.get_bone_global_pose(parent_i)
	var child := skel.get_bone_global_pose(child_i)
	var target: Vector3 = skel.global_transform.affine_inverse() * world_target
	var current := child.origin - parent.origin
	var desired := target - parent.origin
	if current.length_squared() < 1e-8 or desired.length_squared() < 1e-8:
		return
	var a := current.normalized()
	var b := desired.normalized()
	if a.dot(b) > 0.9995:
		return
	var q := Quaternion.IDENTITY
	if a.dot(b) < -0.9995:
		var axis := a.cross(Vector3.UP)
		if axis.length_squared() < 1e-6:
			axis = a.cross(Vector3.RIGHT)
		q = Quaternion(axis.normalized(), PI)
	else:
		q = Quaternion(a, b)
	var spun := (Basis(q) * parent.basis).orthonormalized()
	spun.x *= parent.basis.x.length()
	spun.y *= parent.basis.y.length()
	spun.z *= parent.basis.z.length()
	skel.set_bone_global_pose(parent_i, Transform3D(spun, parent.origin))


func _world(skel: Skeleton3D, bone: int) -> Vector3:
	return (skel.global_transform * skel.get_bone_global_pose(bone)).origin
