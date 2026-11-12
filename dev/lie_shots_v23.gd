extends SceneTree
## Capture lounger + hammock verification shots at 390x844, no HUD.

func _initialize() -> void:
	call_deferred("g")

func g() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	for i in 50:
		await process_frame
	m.demo_mode = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	# Kill ZZZ billboard so shots stay HUD-free even if rest_tick tries to show it.
	if m.zzz and is_instance_valid(m.zzz):
		m.zzz.visible = false
		m.zzz.scale = Vector3.ZERO
		m.zzz.modulate.a = 0.0

	for kind in ["sun", "sleep"]:
		m._begin_rest(kind)
		# Skip walk-up: jump to lying
		m.rest_phase = 4
		m.rest_t = 1.0
		m.set_meta("lie_snapped", false)
		for _p in 4:
			var pl = m.boy.activity(m._act_kind(), 1.0, 1.0, m.gt)
			var swing := Transform3D.IDENTITY
			if kind == "sleep":
				swing = m.island.swing_hammock(0.0)
			m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
			m._snap_lie_contact()
			pl = m.boy.activity(m._act_kind(), 1.0, 1.0, m.gt)
			m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
			m._plant_lie_feet()
			await process_frame
		m.set_meta("lie_snapped", true)
		m.boy.set_process(false)  # don't let _process reseed/clear the foot plant
		for _i in 10:
			var pl2 = m.boy.activity(m._act_kind(), 1.0, 1.0, m.gt)
			var swing2 := Transform3D.IDENTITY
			if kind == "sleep":
				swing2 = m.island.swing_hammock(0.0)
			m.boy.global_transform = swing2 * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl2)
			m._plant_lie_feet()
			if m.zzz and is_instance_valid(m.zzz):
				m.zzz.visible = false
			m.gt += 1.0 / 30.0
			await process_frame
		# Final plant after last frame so gaps see the planted feet.
		var pl3 = m.boy.activity(m._act_kind(), 1.0, 1.0, m.gt)
		var swing3 := Transform3D.IDENTITY
		if kind == "sleep":
			swing3 = m.island.swing_hammock(0.0)
		m.boy.global_transform = swing3 * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl3)
		m._plant_lie_feet()

		var face_n: Vector3 = m.boy.lie_face_normal()
		print(kind, " gaps", m.lie_contact_gaps(), " face_up", face_n.dot(Vector3.UP),
			" penet", m.lie_penetration_depth(), " mesh", m.lie_mesh_penetration_depth())
		m.boy.set_process(true)
		print(kind, " hips", m.boy.lie_bone_world("mixamorig_Hips"),
			" head", m.boy.lie_bone_world("mixamorig_Head"),
			" foot", m.boy.lie_bone_world("mixamorig_LeftFoot"))

		var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
		var foot: Vector3 = m.boy.lie_bone_world("mixamorig_LeftFoot")
		var along := (head - foot).normalized()
		var side := Vector3.UP.cross(along).normalized()
		if side.length_squared() < 1e-6:
			side = m.rest_side
		var prefix := "lounger" if kind == "sun" else "hammock"
		# side / 3-4 closeups
		var shots: Array = [
			["side", atan2(side.x, side.z), 0.08, 2.5, hips.lerp(head, 0.35)],
			["34", atan2(side.x, side.z) + 0.65, 0.28, 2.7, hips.lerp(head, 0.35)],
		]
		# Default gameplay rest camera
		m.rest_cam_yaw = INF
		var rc: Array = m._rest_cam()
		shots.append(["game", rc[1], rc[2], rc[3], rc[0]])
		for s in shots:
			m.cam_target = s[4]
			m.cam_yaw = s[1]
			m.cam_pitch = s[2]
			m.cam_dist = s[3]
			m._apply_camera()
			for _i in 8:
				if m.zzz and is_instance_valid(m.zzz):
					m.zzz.visible = false
				await process_frame
			var path := "/workspace/screenshots/v23/%s_%s.png" % [prefix, s[0]]
			vp.get_texture().get_image().save_png(path)
			print("SHOT ", path)
		m._wake()
		m.mode = m.Mode.EXPLORE
		m.boy.end_activity()
		await process_frame

	quit(0)
