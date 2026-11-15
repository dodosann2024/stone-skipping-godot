extends SceneTree
func _initialize():
	call_deferred("go")
func go():
	var ps = load("res://main.tscn")
	var m = ps.instantiate()
	root.add_child(m)
	await create_timer(0.4).timeout
	var skel: Skeleton3D = m.boy.skel
	var fi = skel.find_bone("mixamorig_LeftFoot")
	var g: Ground = m.ground_sys
	skel.set_bone_global_pose_override(fi, Transform3D.IDENTITY, 0.0, false)
	skel.force_update_transform()
	var ankle0: Vector3 = skel.global_transform * skel.get_bone_global_pose(fi).origin
	var hit = g.ray_foot(ankle0, m.boy.global_position.y)
	var want_y: float = float(hit.position.y) + m.boy.sole_offset + 0.008
	var xf: Transform3D = skel.get_bone_global_pose(fi) # skeleton space
	xf.origin = skel.global_transform.affine_inverse() * Vector3(ankle0.x, want_y, ankle0.z)
	# Actually origin in skeleton space:
	var world = skel.global_transform * skel.get_bone_global_pose(fi)
	world.origin = Vector3(ankle0.x, want_y, ankle0.z)
	var skel_xf = skel.global_transform.affine_inverse() * world
	skel.set_bone_global_pose(fi, skel_xf)
	skel.force_update_all_bone_transforms()
	var after: Vector3 = skel.global_transform * skel.get_bone_global_pose(fi).origin
	print("set_bone_global_pose err_cm=", (after.y - want_y)*100.0, " after=", after)
	# also set_bone_pose Transform3D
	skel.reset_bone_pose(fi)
	skel.force_update_transform()
	world = skel.global_transform * skel.get_bone_global_pose(fi)
	world.origin = Vector3(ankle0.x, want_y, ankle0.z)
	var parent_i = skel.get_bone_parent(fi)
	var parent_g = skel.get_bone_global_pose(parent_i)
	var desired = skel.global_transform.affine_inverse() * world
	var local = parent_g.affine_inverse() * desired
	var rest = skel.get_bone_rest(fi)
	var pose = rest.affine_inverse() * local
	skel.set_bone_pose(fi, pose)
	skel.force_update_all_bone_transforms()
	after = skel.global_transform * skel.get_bone_global_pose(fi).origin
	print("set_bone_pose err_cm=", (after.y - want_y)*100.0, " after=", after)
	quit()
