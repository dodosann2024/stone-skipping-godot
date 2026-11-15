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
	var dur := 1.05
	var u := clampf(phase / dur, 0.0, 1.0)
	var s := clampf((phase - 0.08) / 0.7, 0.0, 1.0)
	var fwd := -skel.global_transform.basis.z
	fwd.y = 0.0
	fwd = Vector3(0, 0, -1) if fwd.length_squared() < 1e-6 else fwd.normalized()
	var right := skel.global_transform.basis.x
	right.y = 0.0
	right = Vector3(1, 0, 0) if right.length_squared() < 1e-6 else right.normalized()
	if _bi[6] >= 0:
		var hp := skel.get_bone_pose(_bi[6])
		# Pose units are pre-scale. FootIK plants the soles after this drop.
		var drop := (0.16 if crouch else 0.09) / Constants.MODEL_SCALE
		hp.origin.y -= drop
		skel.set_bone_pose(_bi[6], hp)
		var spine := _bone(skel, ["mixamorig_Spine", "mixamorig:Spine"])
		if spine >= 0:
			var sp := skel.get_bone_pose(spine)
			var twist := sin(s * PI) * (0.65 if crouch else 0.48)
			sp.basis = sp.basis * Basis(Vector3.UP, -twist)
			skel.set_bone_pose(spine, sp)
		var spine2 := _bone(skel, ["mixamorig_Spine2", "mixamorig:Spine2"])
		if spine2 >= 0:
			var s2 := skel.get_bone_pose(spine2)
			s2.basis = s2.basis * Basis(Vector3.UP, -sin(s * PI) * 0.35)
			skel.set_bone_pose(spine2, s2)
		skel.force_update_all_bone_transforms()
	var shoulder := _world(skel, _bi[0])
	var low := -0.34 if crouch else -0.2
	# Back, then fully out to the side below the shoulder, then across the body.
	var cocked := shoulder - fwd * 0.38 + right * 0.18 + Vector3.UP * low
	var side_low := shoulder + right * 0.92 + Vector3.UP * (low - 0.06)
	var across := shoulder + fwd * 0.48 - right * 0.22 + Vector3.UP * (low + 0.08)
	var hand := cocked.lerp(side_low, clampf(s / 0.55, 0.0, 1.0))
	if s >= 0.55:
		hand = side_low.lerp(across, clampf((s - 0.55) / 0.45, 0.0, 1.0))
	var pole := right * 1.1 + Vector3.DOWN * 0.55
	_solve(skel, _bi[0], _bi[1], _bi[2], hand, pole)
	var lsh := _world(skel, _bi[3])
	var aim := lsh + fwd * 0.35 + Vector3.UP * 0.02
	if s > 0.55:
		aim = lsh - right * 0.1 + Vector3.DOWN * 0.35
	_solve(skel, _bi[3], _bi[4], _bi[5], aim, -right + Vector3.DOWN * 0.3)
	if not hold and not _fired and phase >= 0.46:
		_fired = true
		var origin := _world(skel, _bi[2]) + fwd * 0.28
		var speed := 10.4 if crouch else 11.2
		var lift := 1.05 if crouch else 1.55
		emit_signal("released", origin, fwd * speed + Vector3.UP * lift)
	if u >= 1.0:
		playing = false
		emit_signal("finished")


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
