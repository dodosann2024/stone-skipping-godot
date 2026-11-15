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
var mesh_sole_y: Array[float] = [0.0, 0.0]
var mesh_hit_y: Array[float] = [0.0, 0.0]
var plant_hit_y: Array[float] = [0.0, 0.0]
var plant_ankle_xz: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var stance_locked: Array[bool] = [false, false]
var pose_path := "skeleton_modifier_set_bone_pose"
var _hip_lift := 0.0
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
			# Dominant foot/toe weight only. A 0.22 blend pulled in shin verts that
			# sit centimetres under the sandal during a step and made the probe
			# report a burial the picture does not have.
			if w >= 0.55:
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
	# Do not accumulate a hip lift. The skeleton restores bone poses after the
	# skin upload, so the next frame measured the *animation* again and added
	# another 2.9 cm whenever that sole was 8 cm under the ray. After a short
	# walk the accumulator was ~1 m. The HUD printed that risen pose ("gnd
	# 97.8cm") while the sandals in the picture were the planted animation.
	_hip_lift = 0.0
	var fwd := -boy.global_transform.basis.z
	fwd.y = 0.0
	fwd = Vector3(0, 0, -1) if fwd.length_squared() < 1e-6 else fwd.normalized()
	for side in range(2):
		if _foot_bi[side] < 0 or _up_bi[side] < 0 or _knee_bi[side] < 0:
			stance_locked[side] = false
			continue
		var ankle: Vector3 = _world_xf(skel, _foot_bi[side]).origin
		var nrm := ground.normal(ankle.x, ankle.z, body_y)
		stance_locked[side] = true
		if proof == "lift" and side == 0:
			var target := ankle
			target.y += 0.42
			var pole := ankle + fwd * 0.62 + Vector3(0, 0.42, 0)
			_two_bone(skel, side, target, pole, nrm)
			continue
		# Slide the foot bone so the skinned sole (the uploaded matrix) rests
		# on the surface. Both shoes — a swing foot left in the air fails the bar.
		var sole0 := _lowest_sole(skel, side)
		if sole0.y > 500.0:
			sole0 = Vector3(ankle.x, ankle.y - sole_offset, ankle.z)
		# Freeze the surface for this foot. Re-querying after each nudge let a
		# slope face above the shoe climb with the foot, so the gap never closed.
		var hit_y := _surface_under(sole0.x, sole0.z, sole0.y, body_y)
		plant_hit_y[side] = hit_y
		plant_ankle_xz[side] = Vector2(sole0.x, sole0.z)
		for _pass in range(4):
			var sole_p := _lowest_sole(skel, side)
			if sole_p.y > 500.0:
				break
			var nudge := clampf(SOLE_TARGET - (sole_p.y - hit_y), -0.20, 0.20)
			if absf(nudge) <= 0.0015:
				break
			var foot_xf := _world_xf(skel, _foot_bi[side])
			foot_xf.origin.y += nudge
			_set_world(skel, _foot_bi[side], foot_xf)
		# A blended shoe vert only moves by its foot weight. Overshoot the bone
		# once so the skinned sole, not the bone origin, lands on the hit.
		var sole_end := _lowest_sole(skel, side)
		if sole_end.y < 500.0:
			var left := SOLE_TARGET - (sole_end.y - hit_y)
			if absf(left) > 0.004:
				var foot_xf2 := _world_xf(skel, _foot_bi[side])
				foot_xf2.origin.y += clampf(left / 0.82, -0.16, 0.16)
				_set_world(skel, _foot_bi[side], foot_xf2)


## Swing the foot by rotating the knee only. Bone lengths stay the animated
## lengths, so a bad target cannot stretch the leg into a stilt.
func _rotate_knee(skel: Skeleton3D, side: int, delta_y: float) -> void:
	var knee_xf := _world_xf(skel, _knee_bi[side])
	var foot_xf := _world_xf(skel, _foot_bi[side])
	var shin := foot_xf.origin - knee_xf.origin
	var axis := shin.cross(Vector3.UP)
	if axis.length_squared() < 1e-8:
		axis = knee_xf.basis.x
	else:
		axis = axis.normalized()
	var lever := maxf(shin.length(), 0.12)
	var ang := clampf(delta_y / lever, -0.55, 0.55)
	var before_y := foot_xf.origin.y
	var new_basis := Basis(Quaternion(axis, ang)) * knee_xf.basis
	_set_world(skel, _knee_bi[side], Transform3D(new_basis.orthonormalized(), knee_xf.origin))
	var after_y := _world_xf(skel, _foot_bi[side]).origin.y
	if (after_y - before_y) * delta_y < 0.0:
		var flipped := Basis(Quaternion(axis, -ang)) * knee_xf.basis
		_set_world(skel, _knee_bi[side], Transform3D(flipped.orthonormalized(), knee_xf.origin))


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
	for vi in idxs:
		var fw := 0.0
		for j in 4:
			var bj: int = _bones[vi * 4 + j]
			if bj == foot_b or bj == toe_b:
				fw += _weights[vi * 4 + j]
		# Almost fully on the shoe. Blended shin verts stay under the sandal
		# when the foot bone lifts, and the probe was reading those.
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
	var gaps: Array[float] = []
	for side in range(2):
		var ankle := Vector3.ZERO
		if _foot_bi[side] >= 0:
			ankle = _world_xf(skel, _foot_bi[side]).origin
		# Drawn sole only. The old ankle-minus-offset fallback is what disagreed
		# with the picture by tens of centimetres.
		var sole_p := _lowest_sole(skel, side)
		var sy := sole_p.y
		var xz := Vector2(sole_p.x, sole_p.z)
		if sy > 500.0:
			sy = ankle.y - sole_offset
			xz = Vector2(ankle.x, ankle.z)
		var hy := plant_hit_y[side]
		if absf(hy - sy) > 0.35 or absf(hy) < 0.001:
			hy = _surface_under(xz.x, xz.y, sy, boy.global_position.y) if ground != null else sy
		mesh_sole_y[side] = sy
		mesh_hit_y[side] = hy
		plant_hit_y[side] = hy
		plant_ankle_xz[side] = xz
		gaps.append(sy - hy)
	mesh_gap_min = minf(gaps[0], gaps[1])
	mesh_gap_max = maxf(gaps[0], gaps[1])
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
		var a0 := _world_xf(skel, _foot_bi[0]).origin.y if _foot_bi[0] >= 0 else 0.0
		print("SOLE_MESH gap_cm %.2f..%.2f sole_y %.3f %.3f ankle0 %.3f body_y %.3f" % [
			mesh_gap_min * 100.0, mesh_gap_max * 100.0, mesh_sole_y[0], mesh_sole_y[1],
			a0, boy.global_position.y])
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
