extends SceneTree
## Final clean seats/hammock/face/walk without debug markers.

func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 50:
		await process_frame
	m.demo_mode = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	if m.zzz and is_instance_valid(m.zzz):
		m.zzz.visible = false
	if not m.night_on:
		m.night_btn.pressed.emit()
		for _i in 90:
			await process_frame

	for i in m.island.seats.size():
		var st: Dictionary = m.island.seats[i]
		if st["name"] == "躺椅":
			continue
		m.seat_i = i
		m.seat_ap = st["approach"]
		m.seat_face = st["face"]
		m._begin_rest("seat")
		m.rest_phase = 4
		m.seat_lying = false
		for _p in 20:
			m.boy.activity("seat", 1.0, 0.0, m.gt)
			m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
			m._snap_sit_contact()
			await process_frame
		m.boy.bake_pose_mesh()
		var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		var face: Vector3 = (st["face"] as Vector3).normalized()
		var side: Vector3 = face.cross(Vector3.UP).normalized()
		var fwd: Vector3 = (-m.rest_sit_b.z).normalized()
		var nm := str(st["name"]).replace(" ", "")
		var prefix := "seat%d_%s" % [i, nm]
		print("SEAT%d elev=%.1f fwd=%.2f clear=%.1fcm" % [
			i, m.boy.sit_thigh_elev_deg(),
			(m.boy.lie_bone_world("mixamorig_LeftLeg") - hips).normalized().dot(fwd),
			(hips.y - (st["top"] as Vector3).y) * 100.0
		])
		await _still(m, vp, prefix + "_side", hips + fwd * 0.05, atan2(side.x, side.z), 0.02, 3.1)
		await _still(m, vp, prefix + "_front", hips + Vector3(0, 0.04, 0), atan2(-face.x, -face.z), 0.10, 2.7)
		m.boy.restore_pose_mesh()
		m._wake()
		m.mode = m.Mode.EXPLORE
		m.boy.end_activity()

	# Hammock sit — night + strong body fill, camera outside along axis
	m._begin_rest("sleep")
	m.rest_phase = 2
	for _p in 18:
		var pl = m.boy.activity("sleep", 1.0, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		m._update_hammock_load()
		await process_frame
	# Boost night fill for hammock stills (fabric shadows crush body).
	if m.boy.face_fill:
		m.boy.face_fill.light_energy = 1.8
		m.boy.face_fill.omni_range = 2.0
	if m.boy._night_body:
		m.boy._night_body.light_energy = 1.6
		m.boy._night_body.omni_range = 2.2
	m.boy.bake_pose_mesh()
	var hh: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	var along: Vector3 = (m.island.hammock_b - m.island.hammock_a).normalized()
	var fwd_h: Vector3 = (-m.rest_sit_b.z).normalized()
	print("HAMMOCK elev=%.1f thigh_fwd=%.2f" % [
		m.boy.sit_thigh_elev_deg(),
		(m.boy.lie_bone_world("mixamorig_LeftLeg") - hh).normalized().dot(fwd_h)
	])
	await _still(m, vp, "hammock_sit", hh + fwd_h * 0.06, atan2(along.x, along.z), 0.04, 3.8)
	await _still(m, vp, "hammock_exit", hh + Vector3(0, 0.08, 0), atan2(m.rest_side.x, m.rest_side.z) + PI * 0.75, 0.1, 3.6)
	m.boy.restore_pose_mesh()
	m.island.set_hammock_load([] as Array[Vector3])
	m._wake()
	m.mode = m.Mode.EXPLORE
	m.boy.end_activity()

	# face_sleep day
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 90:
			await process_frame
	m._begin_rest("sun")
	m.rest_phase = 4
	m.set_meta("lie_snapped", false)
	for _p in 28:
		m.boy.clear_foot_plant()
		var pl4 = m.boy.activity("sun", 1.0, 1.0, m.gt)
		m.boy.global_transform = Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl4)
		m._snap_lie_contact()
		m._plant_lie_feet()
		await process_frame
	m.set_meta("lie_snapped", true)
	m.boy.expr = "sleep"
	m.boy.act_kind = "sun"
	m.boy.act_lie_k = 1.0
	for _i in 30:
		m.boy._update_face(0.1)
		await process_frame
	m.boy.bake_pose_mesh()
	for lid in [m.boy._eyelid_l, m.boy._eyelid_r]:
		lid.visible = true
		lid.scale = Vector3(1.35, 2.2, 1.0)
		lid.position.y = 0.05
		lid.position.z = -0.108
	m.island.visible = false
	var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	var face_n: Vector3 = (-m.rest_lie_b.z).normalized()
	var side_s: Vector3 = m.rest_side.normalized()
	var look_f: Vector3 = head + face_n * 0.06
	var cam_f: Vector3 = head + side_s * 0.42 + face_n * 0.42 + Vector3.UP * 0.06
	var to_f: Vector3 = look_f - cam_f
	await _still_face(m, vp, "face_sleep", look_f, atan2(-to_f.x, -to_f.z),
		asin(clampf((-to_f).normalized().y, -0.5, 0.5)), cam_f.distance_to(look_f))
	m.island.visible = true
	m.boy.restore_pose_mesh()

	# Walk/run filmstrips — phases at peak stride
	await _gait(m, vp, "walk", 1.25)
	await _gait(m, vp, "run", 2.25)
	print("FINAL done")
	quit(0)


func _gait(m, vp, tag: String, speed: float) -> void:
	m._place(Vector3(4, 0, -8), 0.0)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3.ZERO
	m.boy.set_idle()
	for _i in 6:
		await process_frame
	m.boy.anim = "move"
	m.boy.set_move(speed)
	m.boy.move_w = 1.0
	m.boy.act_w = 0.0
	m.boy.run_k = 0.0 if tag == "walk" else 1.0
	m.boy.pivoting = false
	m.boy.has_prev = false
	for _w in 12:
		m.boy.phase = 0.15
		m.boy.move_w = 1.0
		m.boy._apply_mixer()
		m.boy._polish_gait(1.0 / 30.0)
		await process_frame
	var n := 8
	var strip := Image.create(390 * n, 844, false, Image.FORMAT_RGBA8)
	# Peak stride samples from gait_arm_diag (0.12/0.38/0.62/0.88).
	var phases: Array[float] = [0.10, 0.20, 0.32, 0.42, 0.55, 0.68, 0.80, 0.92]
	for f in n:
		m.boy.phase = phases[f]
		m.boy.move_w = 1.0
		m.boy.act_w = 0.0
		m.boy.run_k = 0.0 if tag == "walk" else 1.0
		m.boy.pivoting = false
		m.boy._apply_mixer()
		m.boy._polish_gait(1.0 / 30.0)
		m.boy.bake_pose_mesh()
		var wt: Vector3 = m.player.global_position + Vector3(0, 0.65, 0)
		m.demo_cam = true
		m.cam_fixed = true
		m.cam_target = wt
		m.cam_yaw = PI * 0.5
		m.cam_pitch = 0.04
		m.cam_dist = 2.55
		for _i in 4:
			m.boy.phase = phases[f]
			m.boy.move_w = 1.0
			m.boy._apply_mixer()
			m.boy._polish_gait(1.0 / 30.0)
			m.boy.bake_pose_mesh()
			m._apply_camera()
			await process_frame
		strip.blit_rect(vp.get_texture().get_image(), Rect2i(0, 0, 390, 844), Vector2i(f * 390, 0))
		m.boy.restore_pose_mesh()
	strip.save_png("/workspace/screenshots/v24/%s_filmstrip.png" % tag)
	print("SHOT ", tag, "_filmstrip")


func _still(m, vp, name: String, target: Vector3, yaw: float, pitch: float, dist: float) -> void:
	m.demo_cam = true
	m.cam_fixed = true
	for _i in 5:
		if m.mode == m.Mode.REST and m.rest_kind == "seat" and not m.seat_lying:
			m.boy.activity("seat", 1.0, 0.0, m.gt)
			m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		elif m.mode == m.Mode.REST and m.rest_kind == "sleep":
			m.boy.activity("sleep", 1.0, 0.0, m.gt)
			m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
			m._update_hammock_load()
		m.cam_target = target
		m.cam_yaw = yaw
		m.cam_pitch = pitch
		m.cam_dist = dist
		m._apply_camera()
		await process_frame
	m.boy.bake_pose_mesh()
	for _b in 3:
		m._apply_camera()
		await process_frame
	vp.get_texture().get_image().save_png("/workspace/screenshots/v24/%s.png" % name)
	print("SHOT ", name)


func _still_face(m, vp, name: String, target: Vector3, yaw: float, pitch: float, dist: float) -> void:
	m.demo_cam = true
	m.cam_fixed = true
	m.island.visible = false
	for _i in 8:
		for lid in [m.boy._eyelid_l, m.boy._eyelid_r]:
			lid.visible = true
			lid.scale = Vector3(1.35, 2.2, 1.0)
			lid.position.y = 0.05
			lid.position.z = -0.108
		m.cam_target = target
		m.cam_yaw = yaw
		m.cam_pitch = pitch
		m.cam_dist = dist
		m._apply_camera()
		await process_frame
	vp.get_texture().get_image().save_png("/workspace/screenshots/v24/%s.png" % name)
	print("SHOT ", name)
