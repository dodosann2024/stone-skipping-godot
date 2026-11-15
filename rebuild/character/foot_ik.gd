class_name FootIK
extends SkeletonModifier3D
## Stance-only two-bone plant. Bone lengths stay in skeleton space.
## The model is scaled ×1.35 on the node; writing an orthonormalized world
## basis back into a bone drops that scale and shortens the shin.

const FOOT := ["mixamorig_LeftFoot", "mixamorig_RightFoot"]
const TOE := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const UP := ["mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"]
const KNEE := ["mixamorig_LeftLeg", "mixamorig_RightLeg"]
const HIPS := "mixamorig_Hips"

var ground: Ground
var weight: Array[float] = [0.0, 0.0]
var sole_gap: Array[float] = [0.0, 0.0]
var skate_m := 0.0
var shin_ratio: Array[float] = [1.0, 1.0]
var outsole_drop := 0.15
var contact_y := 0.0
var _bi: Array[int] = [-1, -1, -1, -1, -1, -1, -1, -1]
var _hips := -1
var _lock: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _locked: Array[bool] = [false, false]
var _prev: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _rest_shin: Array[float] = [0.0, 0.0]
var _drop := 0.0
var _drop_v := 0.0
var _ready := false
var paused := false


func _process_modification_with_delta(delta: float) -> void:
	if paused:
		return
	var skel := get_skeleton()
	if skel == null or ground == null:
		return
	if delta <= 0.0:
		delta = 1.0 / 60.0
	_bind(skel)
	_strip_root(skel)
	if not _ready:
		_measure_drop(skel)
		_ready = true
	var ankle: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	for side in 2:
		ankle[side] = _world(skel, _bi[side]).origin
	var raw: Array[float] = [1.0, 1.0]
	var above: Array[float] = [0.0, 0.0]
	for side in 2:
		var gy := ground.height(ankle[side].x, ankle[side].z)
		above[side] = (ankle[side].y - outsole_drop) - _surface_y(gy, gy, contact_y if contact_y != 0.0 else ankle[side].y)
	for side in 2:
		var rel: float = above[side] - above[1 - side]
		raw[side] = clampf(1.0 - rel / 0.05, 0.0, 1.0)
	for side in 2:
		var ease := 1.0 - exp(-delta / 0.07)
		weight[side] = lerpf(weight[side], raw[side], ease)
		var here := Vector2(ankle[side].x, ankle[side].z)
		if raw[side] >= 0.98:
			if not _locked[side] or here.distance_to(_lock[side]) > 0.40:
				_locked[side] = true
				_lock[side] = here
		elif raw[side] < 0.45:
			_locked[side] = false
	_pelvis(skel, delta, ankle, raw)
	skate_m = 0.0
	for side in 2:
		if weight[side] < 0.04:
			_prev[side] = Vector2(ankle[side].x, ankle[side].z)
			continue
		_plant(skel, side, ankle[side])
	_record(skel)


func _bind(skel: Skeleton3D) -> void:
	if _hips >= 0:
		return
	_hips = skel.find_bone(HIPS)
	for side in 2:
		_bi[side] = skel.find_bone(FOOT[side])
		_bi[2 + side] = skel.find_bone(TOE[side])
		_bi[4 + side] = skel.find_bone(UP[side])
		_bi[6 + side] = skel.find_bone(KNEE[side])


func _strip_root(skel: Skeleton3D) -> void:
	if _hips < 0:
		return
	var pose := skel.get_bone_pose(_hips)
	var rest := skel.get_bone_rest(_hips)
	pose.origin.x = rest.origin.x
	pose.origin.z = rest.origin.z
	skel.set_bone_pose(_hips, pose)


func _measure_drop(skel: Skeleton3D) -> void:
	var ankle := _world(skel, _bi[0]).origin
	var toe := _world(skel, _bi[2]).origin
	outsole_drop = maxf(ankle.y - toe.y, 0.08) + Constants.SANDAL_BELOW
	outsole_drop = clampf(outsole_drop, 0.08, 0.18)


func _plant(skel: Skeleton3D, side: int, ankle: Vector3) -> void:
	var fwd := -skel.global_transform.basis.z
	fwd.y = 0.0
	fwd = Vector3(0, 0, -1) if fwd.length_squared() < 1e-6 else fwd.normalized()
	var xz := Vector2(ankle.x, ankle.z)
	var body_xz := Vector2(skel.global_position.x, skel.global_position.z)
	if _locked[side] and body_xz.distance_to(_lock[side]) > 0.22:
		_locked[side] = false
	if _locked[side]:
		xz = _lock[side]
	var heel := xz - Vector2(fwd.x, fwd.z) * 0.05
	var toe := xz + Vector2(fwd.x, fwd.z) * 0.06
	var yh := ground.height(heel.x, heel.y)
	var yt := ground.height(toe.x, toe.y)
	var gy := _surface_y(yh, yt, contact_y if contact_y != 0.0 else ankle.y)
	var n := _normal(heel, yh, toe, yt, fwd)
	var up_i: int = _bi[4 + side]
	var knee_i: int = _bi[6 + side]
	var foot_i: int = _bi[side]
	var hip_p := _world(skel, up_i).origin
	var reach := hip_p.distance_to(_world(skel, knee_i).origin) + _world(skel, knee_i).origin.distance_to(ankle)
	var planted := Vector3(xz.x, gy + outsole_drop, xz.y)
	if hip_p.distance_to(planted) > reach - 0.015:
		_locked[side] = false
		xz = Vector2(ankle.x, ankle.z)
		yh = ground.height(xz.x, xz.y)
		yt = yh
		gy = _surface_y(yh, yt, contact_y if contact_y != 0.0 else ankle.y)
		planted = Vector3(xz.x, gy + outsole_drop, xz.y)
	var goal := Vector3(xz.x, ankle.y + (planted.y - ankle.y) * weight[side], xz.y)
	var short := ankle.y - planted.y
	if short > 0.004 and short < 0.05 and weight[side] > 0.9 and _hips >= 0:
		var hp := skel.get_bone_pose(_hips)
		hp.origin.y -= minf(short, 0.03) / Constants.MODEL_SCALE
		skel.set_bone_pose(_hips, hp)
		skel.force_update_all_bone_transforms()
		ankle = _world(skel, foot_i).origin
		goal = Vector3(xz.x, planted.y, xz.y)
	var before := _world(skel, knee_i).origin.distance_to(_world(skel, foot_i).origin)
	_solve_leg(skel, up_i, knee_i, foot_i, goal, fwd)
	var after := _world(skel, knee_i).origin.distance_to(_world(skel, foot_i).origin)
	if before > 0.02 and absf(after / before - 1.0) > 0.02:
		return
	_tilt_foot(skel, foot_i, n, weight[side])
	var now := _world(skel, foot_i).origin
	var err := planted.y - now.y
	if absf(err) > 0.001 and absf(err) < 0.04:
		var again := now
		again.y += err
		_solve_leg(skel, up_i, knee_i, foot_i, again, fwd)
		_tilt_foot(skel, foot_i, n, weight[side])
		now = _world(skel, foot_i).origin
	if _locked[side]:
		skate_m = maxf(skate_m, Vector2(now.x, now.z).distance_to(_lock[side]))
	_prev[side] = Vector2(now.x, now.z)
	sole_gap[side] = (now.y - outsole_drop) - gy
	if sole_gap[side] > 0.006 and weight[side] > 0.9 and _hips >= 0:
		var hp := skel.get_bone_pose(_hips)
		hp.origin.y -= minf(sole_gap[side], 0.025) / Constants.MODEL_SCALE
		skel.set_bone_pose(_hips, hp)
		skel.force_update_all_bone_transforms()
		now = _world(skel, foot_i).origin
		sole_gap[side] = (now.y - outsole_drop) - gy


func _solve_leg(skel: Skeleton3D, up_i: int, knee_i: int, foot_i: int, goal: Vector3, fwd: Vector3) -> void:
	var hip := _world(skel, up_i).origin
	var knee := _world(skel, knee_i).origin
	var ankle := _world(skel, foot_i).origin
	var len1 := hip.distance_to(knee)
	var len2 := knee.distance_to(ankle)
	if len1 < 0.01 or len2 < 0.01:
		return
	var to_t := goal - hip
	if to_t.length_squared() < 1e-8:
		return
	var dist := clampf(to_t.length(), absf(len1 - len2) + 0.001, len1 + len2 - 0.001)
	var dir := to_t.normalized()
	var pole := knee - hip
	var along := ankle - hip
	if along.length_squared() > 1e-6:
		var han := along.normalized()
		pole = pole - han * pole.dot(han)
	pole += fwd * 0.15
	if pole.length_squared() < 1e-6:
		pole = fwd
	var ax := dir.cross(pole)
	if ax.length_squared() < 1e-8:
		ax = dir.cross(Vector3.UP)
	ax = ax.normalized()
	var cos_a := clampf((len1 * len1 + dist * dist - len2 * len2) / (2.0 * len1 * dist), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var side_v := ax.cross(dir).normalized()
	var ka := hip + dir * (len1 * cos_a) + side_v * (len1 * sin_a)
	var kb := hip + dir * (len1 * cos_a) - side_v * (len1 * sin_a)
	var knee_pos := ka if ka.distance_squared_to(knee) <= kb.distance_squared_to(knee) else kb
	_aim(skel, up_i, knee_i, knee_pos)
	skel.force_update_all_bone_transforms()
	var nk := _world(skel, knee_i).origin
	var to_a := goal - nk
	if to_a.length_squared() < 1e-8:
		return
	_aim(skel, knee_i, foot_i, nk + to_a.normalized() * len2)
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
	var basis := (Basis(q) * parent.basis).orthonormalized()
	skel.set_bone_global_pose(parent_i, Transform3D(basis, parent.origin))


func _tilt_foot(skel: Skeleton3D, foot_i: int, normal: Vector3, amount: float) -> void:
	var pose := skel.get_bone_global_pose(foot_i)
	var n := (skel.global_transform.basis.inverse() * normal).normalized()
	var fwd := (skel.global_transform.basis.inverse() * (-skel.global_transform.basis.z)).normalized()
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return
	fwd = fwd.normalized()
	var right := Vector3.UP.cross(fwd).normalized()
	var pitch := clampf(atan2(fwd.dot(n), n.y), deg_to_rad(-25.0), deg_to_rad(25.0))
	var roll := clampf(atan2(right.dot(n), n.y), deg_to_rad(-15.0), deg_to_rad(15.0))
	var turned := (Basis(right, pitch * amount) * Basis(fwd, roll * amount) * pose.basis).orthonormalized()
	pose.basis = turned
	skel.set_bone_global_pose(foot_i, pose)


func _surface_y(yh: float, yt: float, hint: float) -> float:
	var hits: Array[float] = []
	if yh > -1.5:
		hits.append(yh)
	if yt > -1.5:
		hits.append(yt)
	if hits.is_empty():
		return hint
	if hits.size() == 2 and absf(hits[0] - hits[1]) <= 0.16:
		return minf(hits[0], hits[1])
	var best: float = hits[0]
	var best_d := absf(best - hint)
	for h in hits:
		var d := absf(h - hint)
		if d < best_d:
			best = h
			best_d = d
	if best_d > 0.45:
		return hint
	return best


func _normal(heel: Vector2, yh: float, toe: Vector2, yt: float, fwd: Vector3) -> Vector3:
	var h := Vector3(heel.x, yh, heel.y)
	var t := Vector3(toe.x, yt, toe.y)
	var across := Vector3(-fwd.z, 0.0, fwd.x)
	var n := (t - h).cross(across)
	if n.length_squared() < 1e-8 or n.y < 0.2:
		return Vector3.UP
	return n.normalized()


func _pelvis(skel: Skeleton3D, delta: float, ankle: Array[Vector3], raw: Array[float]) -> void:
	if _hips < 0:
		return
	var active: Array[float] = []
	for side in 2:
		if raw[side] < 0.5:
			continue
		var hip: Vector3 = _world(skel, _bi[4 + side]).origin
		var knee: Vector3 = _world(skel, _bi[6 + side]).origin
		var reach: float = hip.distance_to(knee) + knee.distance_to(ankle[side])
		var gy: float = ground.height(ankle[side].x, ankle[side].z)
		var goal := Vector3(ankle[side].x, gy + outsole_drop, ankle[side].z)
		var need: float = hip.distance_to(goal) - reach
		if need > 0.002:
			active.append(need)
	var want := 0.0
	if active.size() >= 2:
		want = minf(active[0], active[1])
	elif active.size() == 1:
		want = active[0]
	want = clampf(want, 0.0, 0.08) / Constants.MODEL_SCALE
	var sprung := _spring(_drop, want, _drop_v, 0.10, delta)
	_drop = clampf(float(sprung[0]), 0.0, 0.08 / Constants.MODEL_SCALE)
	_drop_v = float(sprung[1])
	if _drop > 0.0005:
		var hp := skel.get_bone_pose(_hips)
		hp.origin.y -= _drop
		skel.set_bone_pose(_hips, hp)


func _spring(cur: float, target: float, vel: float, smooth: float, dt: float) -> Array:
	var omega := 2.0 / maxf(smooth, 0.0001)
	var x := omega * dt
	var exp_x := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - target
	var temp := (vel + omega * change) * dt
	return [target + (change + temp) * exp_x, (vel - omega * temp) * exp_x]


func _record(skel: Skeleton3D) -> void:
	for side in 2:
		var knee: Vector3 = _world(skel, _bi[6 + side]).origin
		var foot: Vector3 = _world(skel, _bi[side]).origin
		var length := knee.distance_to(foot)
		if _rest_shin[side] < 0.01:
			_rest_shin[side] = length
		shin_ratio[side] = length / maxf(_rest_shin[side], 0.05)


func _world(skel: Skeleton3D, bone: int) -> Transform3D:
	if bone < 0:
		return Transform3D.IDENTITY
	return skel.global_transform * skel.get_bone_global_pose(bone)
