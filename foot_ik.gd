class_name FootIK
extends SkeletonModifier3D
## Single foot/pelvis contact owner.
##
## Godot 4.7 Skeleton3D::NOTIFICATION_UPDATE_SKELETON runs modifiers, then
## uploads `global_pose * bind_pose` to the RenderingServer, then RESTORES the
## pre-modifier bone poses. The Compatibility renderer (web export included)
## draws that upload. set_bone_global_pose_override and any pose written after
## the upload are not what the GPU skins. This modifier therefore solves with
## set_bone_pose / set_bone_global_pose inside _process_modification_with_delta,
## and the sole probe samples skinned vertices from those same poses before
## the engine restores them.

const B_FOOT := ["mixamorig_LeftFoot", "mixamorig_RightFoot"]
const B_TOE := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const B_UP := ["mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"]
const B_KNEE := ["mixamorig_LeftLeg", "mixamorig_RightLeg"]
const B_HIPS := "mixamorig_Hips"
const B_HEAD := "mixamorig_Head"
## Stance sole target inside the −1…+1.5 cm bar.
const SOLE_TARGET := 0.008
const MAX_HIP_STEP := 0.029

var boy: CharacterBody3D
var ground: Ground
## "", "lift" (visible proof the modifier draws), "override" (skip modifier so
## an external override can be compared on the web build).
var proof := ""
var sole_offset := 0.055
var pose_ready := false
var posed_head := Vector3(0, -100, 0)
var posed_feet := Vector3(0, -100, 0)
var posed_chest := Vector3(0, -100, 0)
var mesh_gap_min := 0.0
var mesh_gap_max := 0.0
var shin_gap_min := 0.0
var knee_flex_deg: Array[float] = [0.0, 0.0]
var shin_len_ratio: Array[float] = [1.0, 1.0]
var mesh_sole_y: Array[float] = [0.0, 0.0]
var mesh_hit_y: Array[float] = [0.0, 0.0]
var plant_hit_y: Array[float] = [0.0, 0.0]
var plant_ankle_xz: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var stance_locked: Array[bool] = [false, false]
var pose_path := "skeleton_modifier_set_bone_pose"
var _hip_lift := 0.0
## How far the lower animated sole hangs below the origin, metres.
## The root adds this so the sole meets the drawn surface.
var support_hang := 0.0
## Smoothed vertical correction per foot, metres. Never a horizontal slide.
var _foot_corr: Array[float] = [0.0, 0.0]
## Slope trim only. The root already stands on the drawn triangle, so a 12 cm
## hip rescue was burying the shorts in the sand instead of planting the sole.
const MAX_FOOT_CORR := 0.08
const MAX_KNEE_DEG := 115.0
var _ready_mesh := false
var _skin: Skin
var _verts: PackedVector3Array = PackedVector3Array()
var _bones: PackedInt32Array = PackedInt32Array()
var _weights: PackedFloat32Array = PackedFloat32Array()
var _bind: Array[Transform3D] = []
var _foot_idx: Array = [[], []]  # vertex indices per side
var _foot_bi: Array[int] = [-1, -1]
var _toe_bi: Array[int] = [-1, -1]
var _up_bi: Array[int] = [-1, -1]
var _knee_bi: Array[int] = [-1, -1]
var _hips_bi := -1
var _head_bi := -1
var _shin_rest: Array[float] = [0.2, 0.2]


func setup(p_boy: CharacterBody3D, p_ground: Ground) -> void:
	boy = p_boy
	ground = p_ground
	influence = 1.0
	active = true


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or boy == null or ground == null:
		return
	if delta <= 0.0:
		delta = 0.016
	_ensure_mesh(skel)
	if proof == "override":
		# Leave the external global-pose override untouched so a web screenshot
		# can show whether that channel is in the skin upload.
		_measure_and_store(skel)
		return
	_clear_leg_overrides(skel)
	var anim := str(boy.anim)
	var hold_pose := anim in ["activity", "prop_clip", "charge", "throw", "react"]
	if not hold_pose:
		_solve(skel, delta)
	_measure_and_store(skel)


func _ensure_mesh(skel: Skeleton3D) -> void:
	if _ready_mesh:
		return
	_hips_bi = skel.find_bone(B_HIPS)
	_head_bi = skel.find_bone(B_HEAD)
	for side in range(2):
		_foot_bi[side] = skel.find_bone(B_FOOT[side])
		_toe_bi[side] = skel.find_bone(B_TOE[side])
		_up_bi[side] = skel.find_bone(B_UP[side])
		_knee_bi[side] = skel.find_bone(B_KNEE[side])
	var mi := _body_mesh(skel)
	if mi == null or mi.mesh == null or mi.skin == null:
		return
	var mesh := mi.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() < 1:
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones_a = arrays[Mesh.ARRAY_BONES]
	var weights_a = arrays[Mesh.ARRAY_WEIGHTS]
	if verts.is_empty() or bones_a == null or weights_a == null:
		return
	_verts = verts
	_bones = PackedInt32Array()
	_bones.resize(verts.size() * 4)
	_weights = PackedFloat32Array()
	_weights.resize(verts.size() * 4)
	for i in verts.size() * 4:
		_bones[i] = int(bones_a[i])
		_weights[i] = float(weights_a[i])
	_skin = mi.skin
	_bind.clear()
	_bind.resize(skel.get_bone_count())
	for bi in skel.get_bone_count():
		_bind[bi] = skel.get_bone_global_rest(bi).affine_inverse()
	for i in _skin.get_bind_count():
		var bn := str(_skin.get_bind_name(i))
		var bi := skel.find_bone(bn) if bn != "" else _skin.get_bind_bone(i)
		if bi >= 0 and bi < _bind.size():
			_bind[bi] = _skin.get_bind_pose(i)
	_foot_idx = [[], []]
	for vi in verts.size():
		for side in range(2):
			var w := 0.0
			for j in 4:
				var b: int = _bones[vi * 4 + j]
				if b == _foot_bi[side] or b == _toe_bi[side]:
					w += _weights[vi * 4 + j]
			if w >= 0.85:
				(_foot_idx[side] as Array).append(vi)
	# Ankle→sole from the bind (rest) pose, used only when a foot has no weighted verts.
	skel.force_update_all_bone_transforms()
	var drop := 0.055
	for side in range(2):
		if _foot_bi[side] < 0:
			continue
		var ankle_y: float = (_world_xf(skel, _foot_bi[side])).origin.y
		var sy := _min_sole_y(skel, side)
		if sy < 1000.0:
			drop = maxf(drop, ankle_y - sy)
	sole_offset = clampf(drop, 0.03, 0.14)
	for side in range(2):
		if _knee_bi[side] < 0 or _foot_bi[side] < 0:
			continue
		_shin_rest[side] = _world_xf(skel, _knee_bi[side]).origin.distance_to(_world_xf(skel, _foot_bi[side]).origin)
	if boy.get("sole_offset") != null:
		boy.sole_offset = sole_offset
	_ready_mesh = true
	print("FOOT_IK verts L=%d R=%d sole_offset=%.1fcm path=%s" % [
		(_foot_idx[0] as Array).size(), (_foot_idx[1] as Array).size(), sole_offset * 100.0, pose_path])


func _body_mesh(skel: Skeleton3D) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_n := 0
	for c in skel.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var m := (c as MeshInstance3D).mesh
			var n := 0
			if m is ArrayMesh and (m as ArrayMesh).get_surface_count() > 0:
				n = (m as ArrayMesh).surface_get_array_len(0)
			if n > best_n:
				best = c as MeshInstance3D
				best_n = n
	return best


func _clear_leg_overrides(skel: Skeleton3D) -> void:
	for bn in [
		B_UP[0], B_KNEE[0], B_FOOT[0], B_TOE[0],
		B_UP[1], B_KNEE[1], B_FOOT[1], B_TOE[1], B_HIPS,
	]:
		var bi := skel.find_bone(bn)
		if bi >= 0:
			skel.set_bone_global_pose_override(bi, Transform3D.IDENTITY, 0.0, false)


func _solve(skel: Skeleton3D, _delta: float) -> void:
	var body_y := boy.global_position.y
	var fwd := -boy.global_transform.basis.z
	fwd.y = 0.0
	fwd = Vector3(0, 0, -1) if fwd.length_squared() < 1e-6 else fwd.normalized()
	if proof == "lift":
		var ankle0: Vector3 = _world_xf(skel, _foot_bi[0]).origin
		var target := ankle0
		target.y += 0.42
		var pole := ankle0 + fwd * 0.62 + Vector3(0, 0.42, 0)
		_two_bone(skel, 0, target, pole, ground.normal(ankle0.x, ankle0.z, body_y))
		return
	# Vertical correction only. A two-bone aim at a bad face folded him into a
	# crawl and parked a sandal beside the hat, so the foot never moves in XZ
	# and a miss keeps the animated leg.
	var moving := float(boy.move_speed) > 0.12
	var step := maxf(_delta, 0.016) * 3.0
	var gaps: Array[float] = [0.0, 0.0]
	var known: Array[bool] = [false, false]
	var sole_y: Array[float] = [body_y, body_y]
	for side in range(2):
		if _foot_bi[side] < 0:
			stance_locked[side] = false
			_foot_corr[side] = move_toward(_foot_corr[side], 0.0, step)
			continue
		var ankle: Vector3 = _world_xf(skel, _foot_bi[side]).origin
		var shell := _lowest_sole(skel, side)
		var sy := shell.y if shell.y < 500.0 else ankle.y - sole_offset
		sole_y[side] = sy
		var sx := ankle.x
		var sz := ankle.z
		if shell.y < 500.0:
			sx = shell.x
			sz = shell.z
		var surface := _query_surface(sx, sz, sy + 0.25)
		plant_ankle_xz[side] = Vector2(sx, sz)
		if surface < -900.0:
			plant_hit_y[side] = body_y
			stance_locked[side] = false
			_foot_corr[side] = move_toward(_foot_corr[side], 0.0, step)
			continue
		plant_hit_y[side] = surface
		gaps[side] = surface + SOLE_TARGET - sy
		known[side] = true
	# Lowest sole relative to the origin. The root stands that far above the
	# drawn surface so this sole meets it. A swinging foot is above the origin
	# and does not pull the root down.
	var hang := 0.0
	for side in range(2):
		if known[side]:
			hang = maxf(hang, body_y - sole_y[side])
	hang = clampf(hang, 0.0, 0.10)
	# Hold the deepest plant. Tracking every swing would bob the root.
	var hang_step := 0.02 if hang > support_hang else 0.0015
	support_hang = move_toward(support_hang, hang, hang_step)
	# The lower sole is always the plant. The other foot keeps the animation
	# while it is a real swing, more than 6 cm clear of its own triangle.
	var lower := 0 if not known[1] or (known[0] and gaps[0] >= gaps[1]) else 1
	for side in range(2):
		if not known[side]:
			continue
		var gap: float = gaps[side]
		var plant := side == lower or (not moving) or gap > -0.06
		stance_locked[side] = plant
		var want := 0.0
		# Bigger than a slope trim means the root is not on this triangle yet.
		if plant and absf(gap) < 0.12:
			want = clampf(gap, -MAX_FOOT_CORR, MAX_FOOT_CORR)
		# Applied this frame. A smoothed chase left the plant sole 2 cm under
		# for the whole footstrike, which is the bury the bar counts.
		_foot_corr[side] = want
	# A few centimetres of vertical trim once the root is on the drawn surface.
	# Not a 12 cm rescue, and not a knee aim.
	var lift := 0.0
	if known[lower]:
		lift = _foot_corr[lower]
	_hip_lift = clampf(lift, -MAX_FOOT_CORR, MAX_FOOT_CORR)
	if _hips_bi >= 0 and absf(_hip_lift) > 0.001:
		var hp := skel.get_bone_pose(_hips_bi)
		var parent_g := Transform3D.IDENTITY
		var parent := skel.get_bone_parent(_hips_bi)
		if parent >= 0:
			parent_g = skel.get_bone_global_pose(parent)
		var skel_up := skel.global_transform.basis.inverse() * Vector3(0, _hip_lift, 0)
		hp.origin += parent_g.basis.inverse() * skel_up
		skel.set_bone_pose(_hips_bi, hp)


## Swing the foot by rotating one bone. Lengths stay the animated lengths.
## The basis is not orthonormalized: that stripped the 1.35 model scale and
## shortened the shin to about 74%.
func _rotate_knee(skel: Skeleton3D, side: int, delta_y: float) -> void:
	_rotate_bone_y(skel, _knee_bi[side], _foot_bi[side], delta_y)


func _rotate_knee_at(skel: Skeleton3D, bone: int, end_bone: int, delta_y: float) -> void:
	_rotate_bone_y(skel, bone, end_bone, delta_y)


func _rotate_bone_y(skel: Skeleton3D, bone: int, end_bone: int, delta_y: float) -> void:
	if bone < 0 or end_bone < 0:
		return
	var bone_xf := _world_xf(skel, bone)
	var end_xf := _world_xf(skel, end_bone)
	var arm := end_xf.origin - bone_xf.origin
	var axis := arm.cross(Vector3.UP)
	if axis.length_squared() < 1e-8:
		axis = bone_xf.basis.x
	else:
		axis = axis.normalized()
	# axis is perpendicular to the shin, so the foot moves on a circle. A
	# small-angle "delta / length" barely lifts or drops a vertical shin.
	var radial := axis.cross(arm)
	var a := arm.y
	var b := radial.y
	var radius := sqrt(a * a + b * b)
	if radius < 1e-4:
		return
	var target := clampf(a + delta_y, -radius + 0.001, radius - 0.001)
	var alpha := atan2(b, a)
	var acc := acos(clampf(target / radius, -1.0, 1.0))
	var ang_a := alpha - acc
	var ang_b := alpha + acc
	var ang := ang_a if absf(ang_a) <= absf(ang_b) else ang_b
	ang = clampf(ang, -1.15, 1.15)
	if absf(ang) < 1e-4:
		return
	var before_y := end_xf.origin.y
	var new_basis := Basis(Quaternion(axis, ang)) * bone_xf.basis
	_set_world(skel, bone, Transform3D(new_basis, bone_xf.origin))
	var after_y := _world_xf(skel, end_bone).origin.y
	if (after_y - before_y) * delta_y < 0.0:
		var flipped := Basis(Quaternion(axis, -ang)) * bone_xf.basis
		_set_world(skel, bone, Transform3D(flipped, bone_xf.origin))


func _two_bone(skel: Skeleton3D, side: int, want: Vector3, pole: Vector3, normal: Vector3) -> void:
	var hip_xf := _world_xf(skel, _up_bi[side])
	var knee_xf := _world_xf(skel, _knee_bi[side])
	var foot_xf := _world_xf(skel, _foot_bi[side])
	var hip: Vector3 = hip_xf.origin
	var len1 := hip.distance_to(knee_xf.origin)
	var len2 := knee_xf.origin.distance_to(foot_xf.origin)
	if len1 < 1e-4 or len2 < 1e-4:
		return
	var to_t := want - hip
	var reach := len1 + len2 - 0.008
	var dist := clampf(to_t.length(), absf(len1 - len2) + 0.01, reach)
	if to_t.length_squared() < 1e-8:
		return
	var dir := to_t.normalized()
	var pole_dir := pole - hip
	var ax := dir.cross(pole_dir)
	if ax.length_squared() < 1e-8:
		ax = dir.cross(Vector3.FORWARD if absf(dir.y) < 0.9 else Vector3.RIGHT)
	ax = ax.normalized()
	var cos_a := clampf((len1 * len1 + dist * dist - len2 * len2) / (2.0 * len1 * dist), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var side_vec := ax.cross(dir).normalized()
	var knee := hip + dir * (dist * cos_a) + side_vec * (dist * sin_a)
	# Prefer the knee that stays above the ground.
	var knee_alt := hip + dir * (dist * cos_a) - side_vec * (dist * sin_a)
	var gy := ground.height(knee.x, knee.z, boy.global_position.y)
	var gy2 := ground.height(knee_alt.x, knee_alt.z, boy.global_position.y)
	if knee_alt.y - gy2 > knee.y - gy:
		knee = knee_alt
		gy = gy2
	if knee.y < gy + 0.04:
		knee.y = gy + 0.04
	_aim_bone(skel, _up_bi[side], hip_xf, knee - hip)
	_aim_bone(skel, _knee_bi[side], _world_xf(skel, _knee_bi[side]), want - knee)
	var foot := _world_xf(skel, _foot_bi[side])
	foot.origin = want
	var up := foot.basis.y.normalized()
	var axis := up.cross(normal)
	if axis.length_squared() > 1e-8:
		var ang := clampf(up.angle_to(normal), -0.4, 0.4)
		foot.basis = foot.basis.rotated(axis.normalized(), ang)
	_set_world(skel, _foot_bi[side], foot)
	# One more ankle pin: child writes can leave the foot short of the sole target.
	foot = _world_xf(skel, _foot_bi[side])
	var sy := _min_sole_y(skel, side)
	if sy < 500.0 and proof != "lift":
		var hy := plant_hit_y[side]
		var err := (hy + SOLE_TARGET) - sy
		if stance_locked[side] or err > 0.0:
			foot.origin.y += err
			_set_world(skel, _foot_bi[side], foot)


func _aim_bone(skel: Skeleton3D, bone: int, xf: Transform3D, along: Vector3) -> void:
	if along.length_squared() < 1e-8:
		return
	var y := along.normalized()
	var x := xf.basis.x
	if absf(x.dot(y)) > 0.95:
		x = xf.basis.z
	x = (x - y * x.dot(y)).normalized()
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	_set_world(skel, bone, Transform3D(Basis(x, y, z).orthonormalized(), xf.origin))


func _world_xf(skel: Skeleton3D, bone: int) -> Transform3D:
	return skel.global_transform * skel.get_bone_global_pose(bone)


func _set_world(skel: Skeleton3D, bone: int, world_xf: Transform3D) -> void:
	# set_bone_global_pose writes the local pose the skin upload reads.
	skel.set_bone_global_pose(bone, skel.global_transform.affine_inverse() * world_xf)


## Lowest drawn point of this leg: sandal or shin. Same upload matrix as the sole.
## Walkable triangle at or just below the foot. -999 when the query is invalid.
func _query_surface(x: float, z: float, probe_y: float) -> float:
	if ground == null:
		return -999.0
	return ground.height_exact(x, z, probe_y)


## Probe surface, or the controller height when no walkable face contains the foot.
func _foot_surface(x: float, z: float, leg_y: float, body_y: float) -> float:
	var h := _query_surface(x, z, leg_y + 0.12)
	if h < -900.0:
		return body_y
	return h


func _knee_flex_of(skel: Skeleton3D, side: int) -> float:
	if _up_bi[side] < 0 or _knee_bi[side] < 0 or _foot_bi[side] < 0:
		return 0.0
	var hip: Vector3 = _world_xf(skel, _up_bi[side]).origin
	var knee: Vector3 = _world_xf(skel, _knee_bi[side]).origin
	var ankle: Vector3 = _world_xf(skel, _foot_bi[side]).origin
	if hip.distance_squared_to(knee) < 1e-6 or knee.distance_squared_to(ankle) < 1e-6:
		return 0.0
	return rad_to_deg((knee - hip).angle_to(ankle - knee))


func _leg_unsafe(skel: Skeleton3D, side: int) -> bool:
	if _up_bi[side] < 0 or _knee_bi[side] < 0 or _foot_bi[side] < 0:
		return true
	var hip: Vector3 = _world_xf(skel, _up_bi[side]).origin
	var knee: Vector3 = _world_xf(skel, _knee_bi[side]).origin
	var ankle: Vector3 = _world_xf(skel, _foot_bi[side]).origin
	if ankle.y > hip.y - 0.08:
		return true
	if hip.distance_squared_to(knee) < 1e-6 or knee.distance_squared_to(ankle) < 1e-6:
		return true
	var flex := rad_to_deg((knee - hip).angle_to(ankle - knee))
	return flex > MAX_KNEE_DEG


## Two-bone plant. Rotates the thigh and the knee so the ankle reaches the
## triangle. Bone lengths stay put because the foot origin is never written
## and the bases keep their scale.
## Returns how far the shell is still below `target_y`.
func _bend_sole_to(skel: Skeleton3D, side: int, target_y: float) -> float:
	if _up_bi[side] < 0 or _knee_bi[side] < 0 or _foot_bi[side] < 0:
		return 0.0
	var hip: Vector3 = _world_xf(skel, _up_bi[side]).origin
	var knee: Vector3 = _world_xf(skel, _knee_bi[side]).origin
	var ankle: Vector3 = _world_xf(skel, _foot_bi[side]).origin
	var len1 := hip.distance_to(knee)
	var len2 := knee.distance_to(ankle)
	if len1 < 1e-4 or len2 < 1e-4:
		return 0.0
	var drop := ankle.y - _shell_y(skel, side)
	var want := Vector3(ankle.x, target_y + drop, ankle.z)
	# One more pass below uses the post-rotate shell, so this want is the first guess.
	var max_r := len1 + len2 - 0.004
	var min_r := absf(len1 - len2) + 0.01
	var dist := hip.distance_to(want)
	if dist > max_r + 0.002:
		# Straight leg still short of the ground. Hip lift has to cover it.
		return maxf(target_y - _shell_y(skel, side), 0.0)
	dist = clampf(dist, min_r, max_r)
	var cos_k := clampf((len1 * len1 + len2 * len2 - dist * dist) / (2.0 * len1 * len2), -1.0, 1.0)
	# 0° is straight. Past ~110° the knee folds and the shin reads as buried
	# even though the bone length is unchanged. Raise the hips instead.
	if rad_to_deg(PI - acos(cos_k)) > 125.0:
		return maxf(target_y - _shell_y(skel, side), 0.0)
	var dir := (want - hip) / dist
	var fwd := -boy.global_transform.basis.z
	fwd.y = 0.0
	fwd = Vector3(0, 0, -1) if fwd.length_squared() < 1e-6 else fwd.normalized()
	var pole := knee + fwd * 0.35 + Vector3.UP * 0.25
	var ax := dir.cross(pole - hip)
	if ax.length_squared() < 1e-8:
		ax = dir.cross(Vector3.RIGHT)
	ax = ax.normalized()
	var cos_a := clampf((len1 * len1 + dist * dist - len2 * len2) / (2.0 * len1 * dist), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var side_v := ax.cross(dir).normalized()
	var knee_p := hip + dir * (dist * cos_a) + side_v * (dist * sin_a)
	var knee_alt := hip + dir * (dist * cos_a) - side_v * (dist * sin_a)
	if knee_alt.y > knee_p.y:
		knee_p = knee_alt
	_aim_child(skel, _up_bi[side], _knee_bi[side], knee_p - hip)
	var knee_now: Vector3 = _world_xf(skel, _knee_bi[side]).origin
	_aim_child(skel, _knee_bi[side], _foot_bi[side], want - knee_now)
	_pitch_foot(skel, side, target_y)
	return maxf(target_y - _shell_y(skel, side), 0.0)


## Tip the foot bone about its origin so the sandal shell meets the triangle.
## The ankle stays put, so the shin length does not change.
func _pitch_foot(skel: Skeleton3D, side: int, target_y: float) -> void:
	var bone := _foot_bi[side]
	if bone < 0:
		return
	var sy := _shell_y(skel, side)
	var err := target_y - sy
	if absf(err) < 0.003 or absf(err) > 0.08:
		return
	var xf := _world_xf(skel, bone)
	var best := xf
	var best_err := absf(err)
	for axis_v in [xf.basis.x, xf.basis.z]:
		var axis := (axis_v as Vector3).normalized()
		if axis.length_squared() < 0.5:
			continue
		for sgn in [-1.0, 1.0]:
			var ang: float = float(sgn) * clampf(absf(err) / 0.09, 0.0, 0.45)
			var spun := Basis(Quaternion(axis, ang)) * xf.basis
			_set_world(skel, bone, Transform3D(spun, xf.origin))
			var now := absf(target_y - _shell_y(skel, side))
			if now < best_err:
				best_err = now
				best = _world_xf(skel, bone)
	_set_world(skel, bone, best)


## Rotate `bone` so the direction toward `child` matches `along`. Scale stays.
func _aim_child(skel: Skeleton3D, bone: int, child: int, along: Vector3) -> void:
	if along.length_squared() < 1e-8:
		return
	var xf := _world_xf(skel, bone)
	var cur := _world_xf(skel, child).origin - xf.origin
	if cur.length_squared() < 1e-8:
		return
	cur = cur.normalized()
	var y := along.normalized()
	var axis := cur.cross(y)
	var ang := 0.0
	if axis.length_squared() < 1e-8:
		if cur.dot(y) > 0.0:
			return
		axis = xf.basis.x.normalized()
		ang = PI
	else:
		axis = axis.normalized()
		ang = cur.angle_to(y)
	var new_basis := Basis(Quaternion(axis, ang)) * xf.basis
	_set_world(skel, bone, Transform3D(new_basis, xf.origin))


func _shell_y(skel: Skeleton3D, side: int) -> float:
	var shell := _lowest_sole(skel, side)
	if shell.y < 500.0:
		return shell.y
	if _foot_bi[side] < 0:
		return 0.0
	return _world_xf(skel, _foot_bi[side]).origin.y - sole_offset


func _leg_bottom(skel: Skeleton3D, side: int) -> Vector3:
	var sole := _lowest_sole(skel, side)
	var shin := _lowest_on_bone(skel, _knee_bi[side], 0.40)
	if shin.y < sole.y:
		return shin
	return sole


func _lowest_on_bone(skel: Skeleton3D, bone: int, min_w: float) -> Vector3:
	if bone < 0 or _verts.is_empty():
		return Vector3(0, 10000, 0)
	var xfs: Array[Transform3D] = []
	xfs.resize(skel.get_bone_count())
	var seen := {}
	var best_y := 10000.0
	var best := Vector3(0, 10000, 0)
	for vi in _verts.size():
		var bw := 0.0
		for j in 4:
			if _bones[vi * 4 + j] == bone:
				bw += _weights[vi * 4 + j]
		if bw < min_w:
			continue
		var acc := Vector3.ZERO
		var wsum := 0.0
		for j in 4:
			var bi: int = _bones[vi * 4 + j]
			var w: float = _weights[vi * 4 + j]
			if w <= 0.0 or bi < 0 or bi >= xfs.size():
				continue
			if not seen.has(bi):
				xfs[bi] = skel.global_transform * (skel.get_bone_global_pose(bi) * _bind[bi])
				seen[bi] = true
			acc += xfs[bi] * _verts[vi] * w
			wsum += w
		if wsum < 0.01:
			continue
		var p := acc / wsum
		if p.y < best_y:
			best_y = p.y
			best = p
	return best


## Lowest skinned foot vertex. The matrix is the one the skin upload writes:
## skeleton.global * (bone.global_pose * skin.bind_pose).
func _lowest_sole(skel: Skeleton3D, side: int) -> Vector3:
	var idxs: Array = _foot_idx[side]
	if idxs.is_empty() or _verts.is_empty():
		return Vector3(0, 10000, 0)
	var xfs: Array[Transform3D] = []
	xfs.resize(skel.get_bone_count())
	var seen := {}
	var best_y := 10000.0
	var best := Vector3(0, 10000, 0)
	var foot_b := _foot_bi[side]
	var toe_b := _toe_bi[side]
	# A weight leak can sit well below the sandal. The authored ankle drop is
	# sole_offset; anything more than 4.5 cm under that is not the shell.
	var sole_floor := -1000.0
	if foot_b >= 0:
		sole_floor = _world_xf(skel, foot_b).origin.y - sole_offset - 0.045
	for vi in idxs:
		var fw := 0.0
		for j in 4:
			var bj: int = _bones[vi * 4 + j]
			if bj == foot_b or bj == toe_b:
				fw += _weights[vi * 4 + j]
		if fw < 0.85:
			continue
		var acc := Vector3.ZERO
		var wsum := 0.0
		for j in 4:
			var bi: int = _bones[vi * 4 + j]
			var w: float = _weights[vi * 4 + j]
			if w <= 0.0 or bi < 0 or bi >= xfs.size():
				continue
			if not seen.has(bi):
				xfs[bi] = skel.global_transform * (skel.get_bone_global_pose(bi) * _bind[bi])
				seen[bi] = true
			acc += xfs[bi] * _verts[vi] * w
			wsum += w
		if wsum < 0.01:
			continue
		var p := acc / wsum
		if p.y < sole_floor:
			continue
		if p.y < best_y:
			best_y = p.y
			best = p
	return best


## Surface under the shoe. A sky-to-sea ray can miss the top and report a
## shell a metre below a sandal that is sitting on the grass.
func _surface_under(x: float, z: float, sole_y: float, body_y: float) -> float:
	# The walk ray starts in the sky and returns the first triangle, which on a
	# slope is often a face above the sandal. The drawn shoe is the sole we
	# just skinned, so the surface that matters is the one within a few
	# centimetres of that vertex.
	# Several samplers disagree on a slope (the sky ray hits a face above the
	# sandal). Keep the one closest to the skinned sole — that is the surface
	# the picture is standing on.
	var best := ground.height(x, z, sole_y)
	var best_d := absf(best - sole_y)
	var near := ground.ray(Vector3(x, sole_y + 0.08, z), Vector3(x, sole_y - 0.10, z))
	if near.has("position"):
		var n: Vector3 = near.get("normal", Vector3.UP)
		if n.y > 0.25:
			var hy := float(near.position.y)
			var d := absf(hy - sole_y)
			if d < best_d:
				best = hy
				best_d = d
	var dx := x - boy.global_position.x
	var dz := z - boy.global_position.z
	if dx * dx + dz * dz < 0.80 * 0.80:
		var body_h := ground.height(boy.global_position.x, boy.global_position.z, body_y)
		var bd := absf(body_h - sole_y)
		if bd < best_d:
			best = body_h
			best_d = bd
	var gh := Island.ground_h(x, z)
	var gd := absf(gh - sole_y)
	if gd < best_d and gd < 0.20:
		best = gh
	return best


func _min_sole_y(skel: Skeleton3D, side: int) -> float:
	var idxs: Array = _foot_idx[side]
	if idxs.is_empty() or _verts.is_empty():
		return 10000.0
	var xfs: Array[Transform3D] = []
	xfs.resize(skel.get_bone_count())
	var seen := {}
	var best := 10000.0
	for vi in idxs:
		var acc := Vector3.ZERO
		var wsum := 0.0
		for j in 4:
			var bi: int = _bones[vi * 4 + j]
			var w: float = _weights[vi * 4 + j]
			if w <= 0.0 or bi < 0 or bi >= xfs.size():
				continue
			if not seen.has(bi):
				# Same product the renderer uploads: global_pose * skin_bind.
				xfs[bi] = skel.global_transform * skel.get_bone_global_pose(bi) * _bind[bi]
				seen[bi] = true
			acc += xfs[bi] * _verts[vi] * w
			wsum += w
		if wsum < 0.01:
			continue
		best = minf(best, (acc / wsum).y)
	return best


func _measure_and_store(skel: Skeleton3D) -> void:
	var sole_gaps: Array[float] = []
	var shin_gaps: Array[float] = []
	var body_y := boy.global_position.y
	for side in range(2):
		var ankle := Vector3.ZERO
		var knee := Vector3.ZERO
		var hip := Vector3.ZERO
		if _foot_bi[side] >= 0:
			ankle = _world_xf(skel, _foot_bi[side]).origin
		if _knee_bi[side] >= 0:
			knee = _world_xf(skel, _knee_bi[side]).origin
		if _up_bi[side] >= 0:
			hip = _world_xf(skel, _up_bi[side]).origin
		var sole_p := _lowest_sole(skel, side)
		var sy := sole_p.y
		var xz := Vector2(sole_p.x, sole_p.z)
		if sy > 500.0:
			sy = ankle.y - sole_offset
			xz = Vector2(ankle.x, ankle.z)
		var shin_p := _lowest_on_bone(skel, _knee_bi[side], 0.45)
		# Same probe the plant uses, so the score is the triangle the foot aimed at.
		var hy := _query_surface(xz.x, xz.y, body_y) if ground != null else sy
		if hy < -900.0:
			hy = body_y - support_hang
		mesh_sole_y[side] = sy
		mesh_hit_y[side] = hy
		plant_hit_y[side] = hy
		plant_ankle_xz[side] = xz
		sole_gaps.append(sy - hy)
		if shin_p.y < 500.0:
			var shy := _query_surface(shin_p.x, shin_p.z, body_y) if ground != null else shin_p.y
			if shy < -900.0:
				shy = body_y - support_hang
			if absf(shy - hy) < 0.08:
				shin_gaps.append(shin_p.y - shy)
		var shin_len := knee.distance_to(ankle)
		var rest_len := maxf(_shin_rest[side], 0.05)
		shin_len_ratio[side] = shin_len / rest_len
		if hip.distance_squared_to(knee) > 1e-6 and knee.distance_squared_to(ankle) > 1e-6:
			knee_flex_deg[side] = rad_to_deg((knee - hip).angle_to(ankle - knee))
	shin_gap_min = shin_gaps[0] if not shin_gaps.is_empty() else 0.0
	for g in shin_gaps:
		shin_gap_min = minf(shin_gap_min, g)
	mesh_gap_min = sole_gaps[0]
	mesh_gap_max = sole_gaps[0]
	for g in sole_gaps:
		mesh_gap_min = minf(mesh_gap_min, g)
		mesh_gap_max = maxf(mesh_gap_max, g)
	# A shin in the ground is the picture. A shin in the air is a step, not a float.
	if shin_gap_min < mesh_gap_min:
		mesh_gap_min = shin_gap_min
	var feet := Vector3.ZERO
	var n := 0
	for side in range(2):
		if _foot_bi[side] < 0:
			continue
		var p: Vector3 = _world_xf(skel, _foot_bi[side]).origin
		p.y = mesh_sole_y[side]
		feet += p
		n += 1
	if n > 0:
		posed_feet = feet / float(n)
	if _head_bi >= 0:
		posed_head = _world_xf(skel, _head_bi).origin + Vector3(0, 0.16, 0)
	else:
		posed_head = boy.global_position + Vector3(0, 1.15, 0)
	posed_chest = posed_feet.lerp(posed_head, 0.52)
	pose_ready = true
	if Engine.get_process_frames() == 50 or Engine.get_process_frames() == 51:
		print("SOLE_MESH gap_cm %.2f..%.2f shin_cm %.2f knee %.0f/%.0f len %.2f/%.2f hip %.1f sole_y %.3f %.3f body_y %.3f" % [
			mesh_gap_min * 100.0, mesh_gap_max * 100.0, shin_gap_min * 100.0,
			knee_flex_deg[0], knee_flex_deg[1], shin_len_ratio[0], shin_len_ratio[1],
			_hip_lift * 100.0, mesh_sole_y[0], mesh_sole_y[1], boy.global_position.y])
	if boy.get("sole_offset") != null:
		boy.sole_offset = sole_offset
	# Mirror plant flags the rest of the game already reads.
	if boy.get("_stance_locked") != null:
		for side in range(2):
			boy._stance_locked[side] = stance_locked[side]
			boy._plant_hit_y[side] = plant_hit_y[side]
			boy._plant_ankle_xz[side] = plant_ankle_xz[side]


## Editor/dev entry. The live plant is the modifier; this only refreshes the cache.
func measure_sole_offset() -> void:
	var skel := get_skeleton()
	if skel == null and boy != null:
		skel = boy.skel
	if skel != null:
		_ensure_mesh(skel)


func apply() -> void:
	# Kept so older call sites no-op instead of writing a second, undrawn plant.
	pass


func sole_y(side: int) -> float:
	if side >= 0 and side < mesh_sole_y.size() and pose_ready:
		return mesh_sole_y[side]
	return boy.global_position.y if boy else 0.0


func sole_gaps() -> Array:
	return [mesh_gap_min, mesh_gap_max]


static func commit_global(skel: Skeleton3D, bone: int, skel_space: Transform3D, amount: float = 1.0) -> void:
	## Drawable pose (set_bone_global_pose → set_bone_pose). Not an override.
	if bone < 0:
		return
	if amount < 0.999:
		var cur := skel.get_bone_global_pose(bone)
		skel_space = cur.interpolate_with(skel_space, clampf(amount, 0.0, 1.0))
	skel.set_bone_global_pose(bone, skel_space)
