class_name RestPose
extends SkeletonModifier3D
## Recline and a crossed knee on top of a sit clip.
## There is no authored lie clip in the approved library.

var mode := ""
var _bi: Array[int] = []


func _process_modification_with_delta(_delta: float) -> void:
	if mode != "lie":
		return
	var skel := get_skeleton()
	if skel == null:
		return
	_bind(skel)
	if _bi[0] < 0:
		return
	var fwd := -skel.global_transform.basis.z
	fwd.y = 0.0
	fwd = Vector3(0, 0, -1) if fwd.length_squared() < 1e-6 else fwd.normalized()
	var right := skel.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var hip := _world(skel, _bi[0])
	var knee := hip + fwd * 0.16 + Vector3.UP * 0.28
	var other := _world(skel, _bi[4])
	var foot := other + Vector3.UP * 0.06 + fwd * 0.02
	_solve(skel, _bi[0], _bi[1], _bi[2], knee, foot, Vector3.UP)
	if _bi[5] >= 0:
		var pose := skel.get_bone_global_pose(_bi[5])
		var axis := (skel.global_transform.basis.inverse() * right).normalized()
		if axis.length_squared() > 0.5:
			var lean := Basis(axis, deg_to_rad(-22.0))
			pose.basis = (lean * pose.basis).orthonormalized()
			skel.set_bone_global_pose(_bi[5], pose)


func _bind(skel: Skeleton3D) -> void:
	if _bi.size() == 6:
		return
	_bi = [
		_bone(skel, ["mixamorig_LeftUpLeg", "mixamorig:LeftUpLeg"]),
		_bone(skel, ["mixamorig_LeftLeg", "mixamorig:LeftLeg"]),
		_bone(skel, ["mixamorig_LeftFoot", "mixamorig:LeftFoot"]),
		_bone(skel, ["mixamorig_RightUpLeg", "mixamorig:RightUpLeg"]),
		_bone(skel, ["mixamorig_RightLeg", "mixamorig:RightLeg"]),
		_bone(skel, ["mixamorig_Spine", "mixamorig:Spine"]),
	]


func _bone(skel: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := skel.find_bone(n)
		if i >= 0:
			return i
	return -1


func _solve(skel: Skeleton3D, up_i: int, mid_i: int, end_i: int, knee_goal: Vector3, foot_goal: Vector3, _pole_hint: Vector3) -> void:
	var hip := _world(skel, up_i)
	var mid := _world(skel, mid_i)
	var tip := _world(skel, end_i)
	var len1 := hip.distance_to(mid)
	var len2 := mid.distance_to(tip)
	if len1 < 0.01 or len2 < 0.01:
		return
	var to_k := knee_goal - hip
	if to_k.length_squared() < 1e-6:
		return
	_aim(skel, up_i, mid_i, hip + to_k.normalized() * len1)
	skel.force_update_all_bone_transforms()
	var nk := _world(skel, mid_i)
	var to_f := foot_goal - nk
	if to_f.length_squared() < 1e-6:
		return
	_aim(skel, mid_i, end_i, nk + to_f.normalized() * len2)


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
	var q := Quaternion(a, b) if a.dot(b) > -0.9995 else Quaternion(Vector3.UP, PI)
	var basis := (Basis(q) * parent.basis).orthonormalized()
	skel.set_bone_global_pose(parent_i, Transform3D(basis, parent.origin))


func _world(skel: Skeleton3D, bone: int) -> Vector3:
	if bone < 0:
		return Vector3.ZERO
	return (skel.global_transform * skel.get_bone_global_pose(bone)).origin
