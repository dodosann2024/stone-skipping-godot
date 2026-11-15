extends SceneTree
func _initialize():
	call_deferred("go")
func go():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var z0 = m.island.dock_start_z + 6.5
	var y = m._surface(2.6, z0)
	m.player.position = Vector3(2.6, y, z0)
	m._sync_body_pose(true)
	m.face_yaw = -0.4
	m.joy.value = Vector2(0.4, -0.8)
	for i in 80:
		await process_frame
		if i in [28, 29, 30, 31, 59, 60, 61]:
			m.boy._reassert_foot_plants()
			var skel = m.boy.skel
			for side in range(2):
				var fi = skel.find_bone(["mixamorig_LeftFoot","mixamorig_RightFoot"][side])
				var ank: Vector3 = skel.global_transform * skel.get_bone_global_pose(fi).origin
				var hy_plant = m.boy.foot_ik.plant_hit_y[side]
				var hy_h = m.ground_sys.height(ank.x, ank.z, m.player.position.y)
				var hy_c = m.island.collision_h(ank.x, ank.z, m.player.position.y, [m.boy.get_rid()])
				var sole = ank.y - m.boy.sole_offset
				print("f", i, " side", side, " ank=", ank, " hit=", hy_plant, " height=", hy_h, " col_h=", hy_c, " sole-col=", (sole-hy_c)*100.0, " sole-hit=", (sole-hy_plant)*100.0, " want_d=", (ank.y - (hy_plant+m.boy.sole_offset+0.008))*100.0)
	quit()
