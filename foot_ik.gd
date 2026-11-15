class_name FootIK
extends Node
## v37: single foot-plant owner. Writes DRAWABLE poses via Skeleton3D.set_bone_global_pose
## (Godot 4.7 Compatibility skins this channel). No TwoBoneIK3D, no SOLE_CLEAR /
## _contact_lift, no override-only band-aid.

const B_FOOT := ["mixamorig_LeftFoot", "mixamorig_RightFoot"]
const B_TOE := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const B_LEG := [
	["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_LeftToeBase"],
	["mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot", "mixamorig_RightToeBase"],
]
## Target sole ≈ +0.8 cm inside AAA −1…+1.5 cm (walk deformation / web jitter).
const SOLE_PAD := 0.008

var boy: CharacterBody3D
var ground: Ground
var sole_offset := 0.055
var plant_hit_y: Array[float] = [0.0, 0.0]
var plant_ankle_xz: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var stance_locked: Array[bool] = [false, false]


func setup(p_boy: CharacterBody3D, p_ground: Ground) -> void:
	boy = p_boy
	ground = p_ground


func _skel() -> Skeleton3D:
	return boy.skel if boy else null


func measure_sole_offset() -> void:
	var skel := _skel()
	if skel == null:
		return
	skel.reset_bone_poses()
	skel.force_update_transform()
	var best := 0.055
	for side in range(2):
		var fi := skel.find_bone(B_FOOT[side])
		var ti := skel.find_bone(B_TOE[side])
		if fi < 0:
			continue
		var ankle: Vector3 = skel.global_transform * skel.get_bone_global_pose(fi).origin
		var toe_y := ankle.y
		if ti >= 0:
			toe_y = (skel.global_transform * skel.get_bone_global_pose(ti)).origin.y
		best = maxf(best, ankle.y - minf(ankle.y, toe_y) + 0.012)
	sole_offset = clampf(best, 0.045, 0.12)
	if boy.has_method("_apply_mixer"):
		boy.call("_apply_mixer")
	print("FOOT_IK sole_offset=%.1fcm" % [sole_offset * 100.0])


func apply() -> void:
	var skel := _skel()
	if skel == null or ground == null or boy == null:
		return
	var anim: String = str(boy.anim)
	if anim in ["activity", "prop_clip", "charge"]:
		_clear_leg_overrides(skel)
		stance_locked[0] = false
		stance_locked[1] = false
		return
	var model: Node3D = boy.model
	if model != null:
		model.position = boy.model_base + Vector3(boy.hip_shift.x, 0.0, 0.0)
	_clear_leg_overrides(skel)
	skel.force_update_transform()
	var body_y := boy.global_position.y
	var fwd := -boy.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = Vector3(0, 0, -1)
	else:
		fwd = fwd.normalized()
	var inv := skel.global_transform.affine_inverse()
	for side in range(2):
		var fi := skel.find_bone(B_FOOT[side])
		if fi < 0:
			stance_locked[side] = false
			continue
		var ankle: Vector3 = skel.global_transform * skel.get_bone_global_pose(fi).origin
		var hit: Dictionary = ground.ray_foot(ankle, body_y)
		# Prefer Ground.height (same walk sampler as body Y) so plant can't
		# latch onto a lower side-hit while collision_h under the heel is higher.
		var hy := ground.height(ankle.x, ankle.z, body_y)
		if hit.has("position"):
			hy = maxf(hy, float(hit.position.y))
		if hy < -0.35:
			stance_locked[side] = false
			continue
		var want := Vector3(ankle.x, hy + sole_offset + SOLE_PAD, ankle.z)
		var nrm: Vector3 = hit.get("normal", Vector3.UP) if hit.has("normal") else ground.normal(ankle.x, ankle.z, body_y)
		plant_hit_y[side] = hy
		plant_ankle_xz[side] = Vector2(ankle.x, ankle.z)
		stance_locked[side] = true
		var pole := want + fwd * 0.70 + Vector3(0, 0.55, 0)
		_solve_drawable(skel, side, want, pole, nrm, inv)
	# Snapshot override-composed world xforms, CLEAR overrides, then write the
	# drawable pose channel. set_bone_global_pose while an override is active can
	# be ignored — clearing would then reveal the mixer float on web.
	_bake_leg_chain(skel)
	_lift_knees(skel)
	_pin_feet(skel)
	skel.force_update_all_bone_transforms()
	_pin_feet(skel)
	skel.force_update_all_bone_transforms()


func _bake_leg_chain(skel: Skeleton3D) -> void:
	# Hip → knee → foot (toe follows foot pin): snapshot with overrides on.
	var snaps: Array = []  # {bi, world}
	for side in range(2):
		if not stance_locked[side]:
			continue
		for bn in B_LEG[side]:
			if bn.ends_with("ToeBase"):
				continue
			var bi := skel.find_bone(bn)
			if bi < 0:
				continue
			var world_b: Transform3D = skel.global_transform * skel.get_bone_global_pose(bi)
			snaps.append({"bi": bi, "world": world_b})
	_clear_leg_overrides(skel)
	skel.force_update_transform()
	for s in snaps:
		var bi2: int = int(s["bi"])
		var world2: Transform3D = s["world"]
		skel.set_bone_global_pose(bi2, skel.global_transform.affine_inverse() * world2)
	skel.force_update_all_bone_transforms()


func _lift_knees(skel: Skeleton3D) -> void:
	for tag_k in ["Left", "Right"]:
		var ki_k := skel.find_bone("mixamorig_%sLeg" % tag_k)
		if ki_k < 0:
			continue
		var kw: Transform3D = skel.global_transform * skel.get_bone_global_pose(ki_k)
		var kh: Dictionary = ground.ray_foot(kw.origin, boy.global_position.y)
		if kh.has("position") and kw.origin.y < float(kh.position.y) + 0.045:
			kw.origin.y = float(kh.position.y) + 0.045
			skel.set_bone_global_pose(ki_k, skel.global_transform.affine_inverse() * kw)


func _pin_feet(skel: Skeleton3D) -> void:
	for side in range(2):
		if not stance_locked[side]:
			continue
		var fi := skel.find_bone(B_FOOT[side])
		if fi < 0:
			continue
		var want_y: float = plant_hit_y[side] + sole_offset + SOLE_PAD
		var xf: Transform3D = skel.global_transform * skel.get_bone_global_pose(fi)
		xf.origin = Vector3(plant_ankle_xz[side].x, want_y, plant_ankle_xz[side].y)
		skel.set_bone_global_pose(fi, skel.global_transform.affine_inverse() * xf)
		var toe := skel.find_bone(B_TOE[side])
		if toe < 0:
			continue
		var tx: Transform3D = skel.global_transform * skel.get_bone_global_pose(toe)
		var ht: Dictionary = ground.ray_foot(tx.origin, boy.global_position.y)
		var toe_y := want_y - sole_offset + 0.012
		if ht.has("position"):
			toe_y = float(ht.position.y) + 0.012
		tx.origin.y = toe_y
		skel.set_bone_global_pose(toe, skel.global_transform.affine_inverse() * tx)
		# Re-pin foot after toe write (child write can shift parent read).
		xf = skel.global_transform * skel.get_bone_global_pose(fi)
		xf.origin = Vector3(plant_ankle_xz[side].x, want_y, plant_ankle_xz[side].y)
		skel.set_bone_global_pose(fi, skel.global_transform.affine_inverse() * xf)


func _clear_leg_overrides(skel: Skeleton3D) -> void:
	for bn in [
		"mixamorig_LeftUpLeg", "mixamorig_LeftLeg", B_FOOT[0], B_TOE[0],
		"mixamorig_RightUpLeg", "mixamorig_RightLeg", B_FOOT[1], B_TOE[1],
	]:
		var bi := skel.find_bone(bn)
		if bi >= 0:
			skel.set_bone_global_pose_override(bi, Transform3D.IDENTITY, 0.0, false)


## Two-bone solve via overrides (stable chain), then bake each bone with
## set_bone_global_pose so Compatibility skins the same result.
func _solve_drawable(skel: Skeleton3D, side: int, want: Vector3, pole: Vector3, normal: Vector3, inv: Transform3D) -> void:
	var tag := "Left" if side == 0 else "Right"
	var hi := skel.find_bone("mixamorig_%sUpLeg" % tag)
	var ki := skel.find_bone("mixamorig_%sLeg" % tag)
	var fi := skel.find_bone("mixamorig_%sFoot" % tag)
	if hi < 0 or ki < 0 or fi < 0:
		return
	var hip_g: Transform3D = skel.global_transform * skel.get_bone_global_pose(hi)
	var knee_g: Transform3D = skel.global_transform * skel.get_bone_global_pose(ki)
	var foot_g: Transform3D = skel.global_transform * skel.get_bone_global_pose(fi)
	var hip := hip_g.origin
	var len1 := hip.distance_to(knee_g.origin)
	var len2 := knee_g.origin.distance_to(foot_g.origin)
	if len1 < 1e-4 or len2 < 1e-4:
		return
	var to_t := want - hip
	var dist := clampf(to_t.length(), 0.05, len1 + len2 - 0.01)
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
	var knee_a := hip + dir * (dist * cos_a) + side_vec * (dist * sin_a)
	var knee_b := hip + dir * (dist * cos_a) - side_vec * (dist * sin_a)
	var knee := knee_a
	var ha := ground.ray_foot(knee_a, boy.global_position.y)
	var hb := ground.ray_foot(knee_b, boy.global_position.y)
	var dig_a := 0.0 if not ha.has("position") else maxf(0.0, float(ha.position.y) + 0.04 - knee_a.y)
	var dig_b := 0.0 if not hb.has("position") else maxf(0.0, float(hb.position.y) + 0.04 - knee_b.y)
	if dig_b < dig_a:
		knee = knee_b
		ha = hb
	if ha.has("position") and knee.y < float(ha.position.y) + 0.04:
		knee.y = float(ha.position.y) + 0.04
	var thigh_y := (knee - hip).normalized()
	var shin_y := (want - knee).normalized()
	if thigh_y.length_squared() < 1e-8 or shin_y.length_squared() < 1e-8:
		return
	var thigh_x := hip_g.basis.x
	if absf(thigh_x.dot(thigh_y)) > 0.95:
		thigh_x = hip_g.basis.z
	thigh_x = (thigh_x - thigh_y * thigh_x.dot(thigh_y)).normalized()
	var thigh_z := thigh_x.cross(thigh_y).normalized()
	thigh_x = thigh_y.cross(thigh_z).normalized()
	var shin_x := knee_g.basis.x
	if absf(shin_x.dot(shin_y)) > 0.95:
		shin_x = knee_g.basis.z
	shin_x = (shin_x - shin_y * shin_x.dot(shin_y)).normalized()
	var shin_z := shin_x.cross(shin_y).normalized()
	shin_x = shin_y.cross(shin_z).normalized()
	var thigh_xf := inv * Transform3D(Basis(thigh_x, thigh_y, thigh_z).orthonormalized(), hip)
	var shin_xf := inv * Transform3D(Basis(shin_x, shin_y, shin_z).orthonormalized(), knee)
	skel.set_bone_global_pose_override(hi, thigh_xf, 1.0, true)
	skel.set_bone_global_pose_override(ki, shin_xf, 1.0, true)
	var xf: Transform3D = skel.global_transform * skel.get_bone_global_pose(fi)
	xf.origin = want
	var up := xf.basis.y.normalized()
	var axis := up.cross(normal)
	if axis.length_squared() > 1e-8:
		var ang := clampf(up.angle_to(normal), -0.45, 0.45)
		xf.basis = xf.basis.rotated(axis.normalized(), ang)
	skel.set_bone_global_pose_override(fi, inv * xf, 1.0, true)


func sole_y(side: int) -> float:
	var skel := _skel()
	if skel == null:
		return boy.global_position.y if boy else 0.0
	var fi := skel.find_bone(B_FOOT[side])
	if fi < 0:
		return boy.global_position.y
	var ankle: Vector3 = skel.global_transform * skel.get_bone_global_pose(fi).origin
	return ankle.y - sole_offset


func sole_gaps() -> Array:
	var min_g := 0.0
	var max_g := 0.0
	var any := false
	for side in range(2):
		var sy := sole_y(side)
		# Same hit the plant used this frame (not a second sampler).
		var hy := plant_hit_y[side]
		if hy == 0.0 and ground != null:
			var ax := plant_ankle_xz[side].x if plant_ankle_xz[side].length_squared() > 1e-8 else boy.global_position.x
			var az := plant_ankle_xz[side].y if plant_ankle_xz[side].length_squared() > 1e-8 else boy.global_position.z
			hy = ground.height(ax, az, boy.global_position.y)
		var gap := sy - hy
		if not any:
			min_g = gap
			max_g = gap
			any = true
		else:
			min_g = minf(min_g, gap)
			max_g = maxf(max_g, gap)
	return [min_g, max_g]
