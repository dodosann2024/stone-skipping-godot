extends SceneTree
## v24 verification stills at 390×844: seats, hammock stages, fixed cam, face, walk filmstrip.

func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	DirAccess.make_dir_recursive_absolute("/workspace/screenshots/v24")
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
		m.zzz.modulate.a = 0.0
	# Match user night feedback shots.
	if not m.night_on:
		m.night_btn.pressed.emit()
		for _i in 90:
			await process_frame

	# --- Seats: each bench/log front + side ---
	for i in m.island.seats.size():
		var st: Dictionary = m.island.seats[i]
		# Skip lounger here (covered as sun); only benches/logs.
		if st["name"] == "躺椅":
			continue
		m.seat_i = i
		m.seat_ap = st["approach"]
		m.seat_face = st["face"]
		m._begin_rest("seat")
		m.set_process(false)
		m.boy.set_process(false)
		m.rest_phase = 4
		m.rest_t = 1.0
		m.seat_lying = false
		for _p in 10:
			m.boy.activity("seat", 1.0, 0.0, m.gt)
			m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
			m._snap_sit_contact()
			await process_frame
		var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		var face: Vector3 = (st["face"] as Vector3).normalized()
		var side: Vector3 = face.cross(Vector3.UP).normalized()
		var nm := str(st["name"]).replace(" ", "")
		var prefix := "seat%d_%s" % [i, nm]
		await _shot(m, vp, prefix + "_front", hips + Vector3(0, 0.15, 0), atan2(-face.x, -face.z), 0.18, 2.6)
		await _shot(m, vp, prefix + "_side", hips + Vector3(0, 0.15, 0), atan2(side.x, side.z), 0.12, 2.8)
		m.set_process(true)
		m.boy.set_process(true)
		m._wake()
		m.mode = m.Mode.EXPLORE
		m.boy.end_activity()
		await process_frame

	# --- Hammock: enter / sit / hold / exit ---
	m._begin_rest("sleep")
	m.set_process(false)
	m.boy.set_process(false)
	m.rest_phase = 0
	m.player.global_position = m.rest_approach
	m.boy.global_position = m.rest_approach
	m.boy.set_idle()
	m.boy.rotation = Vector3(0, atan2(-m.rest_side.x, -m.rest_side.z), 0)
	for _i in 4:
		await process_frame
	await _shot(m, vp, "hammock_enter", m.rest_approach + Vector3(0, 0.7, 0), atan2(m.rest_side.x, m.rest_side.z) + 0.4, 0.2, 3.4)
	# Sit on fabric
	m.rest_phase = 2
	m.rest_t = 1.0
	var pl = m.boy.activity("sleep", 1.0, 0.0, m.gt)
	m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_seat - m.rest_sit_b * pl)
	m._update_hammock_load()
	for _i in 6:
		await process_frame
	await _shot(m, vp, "hammock_sit", m.boy.lie_bone_world("mixamorig_Hips"), atan2(m.rest_side.x, m.rest_side.z), 0.25, 3.2)
	# Hold lying
	m.rest_phase = 4
	m.rest_t = 1.0
	m.set_meta("lie_snapped", false)
	for _p in 30:
		pl = m.boy.activity("sleep", 1.0, 1.0, m.gt)
		var swing = m.island.swing_hammock(0.0)
		m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
		m._update_hammock_load()
		m._snap_lie_contact()
		await process_frame
	m.set_meta("lie_snapped", true)
	await _shot(m, vp, "hammock_hold", m.boy.lie_bone_world("mixamorig_Hips"), atan2(m.rest_side.x, m.rest_side.z), 0.3, 3.4)
	# Exit
	m.rest_phase = 6
	m.rest_t = 0.5
	pl = m.boy.activity("sleep", 0.5, 0.0, m.gt)
	m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_approach.lerp(m.rest_seat, 0.35) - m.rest_sit_b * pl)
	for _i in 4:
		await process_frame
	await _shot(m, vp, "hammock_exit", m.boy.global_position + Vector3(0, 0.6, 0), atan2(m.rest_side.x, m.rest_side.z) + 0.3, 0.2, 3.4)
	m.set_process(true)
	m.boy.set_process(true)
	m._wake()
	m.mode = m.Mode.EXPLORE
	m.boy.end_activity()

	# --- Fixed camera near/far (UI visible) ---
	m.ui_root.visible = true
	m.cam_fixed = true
	m.fix_target = m.player.global_position + Vector3(0, 0.7, 0)
	m.fix_yaw = m.face_yaw + PI * 0.85
	m.fix_pitch = 0.28
	m.fix_dist = 3.2
	m.cam_target = m.fix_target
	m.cam_yaw = m.fix_yaw
	m.cam_pitch = m.fix_pitch
	m.cam_dist = m.fix_dist
	m._update_ui()
	m._apply_camera()
	for _i in 8:
		await process_frame
	await _shot_raw(vp, "fixed_near")
	m.fix_dist = 11.0
	m.cam_dist = 11.0
	m._apply_camera()
	for _i in 8:
		await process_frame
	await _shot_raw(vp, "fixed_far")
	m.cam_fixed = false
	m.ui_root.visible = false
	m._update_ui()

	# --- Face close-ups (day fill for clarity) ---
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 90:
			await process_frame
	m.boy.set_idle()
	m.boy.set_face_expr("smile")
	m._place(Vector3(1.5, 0, -5.5), PI)
	m.boy.global_position = m.player.global_position
	var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	await _shot(m, vp, "face_smile", head, m.face_yaw + PI, 0.05, 0.72)
	# Capture mid-blink (lids closed).
	m.boy.blink_t = 0.0
	m.boy._update_face(0.02)
	m.boy._update_face(0.02)
	m.boy._eyelid_l.scale.y = 1.35
	m.boy._eyelid_r.scale.y = 1.35
	for _i in 3:
		await process_frame
	head = m.boy.lie_bone_world("mixamorig_Head")
	await _shot(m, vp, "face_blink", head, m.face_yaw + PI, 0.05, 0.72)
	m.boy.set_face_expr("cheer")
	m.boy.react("cheer")
	for _i in 12:
		m.boy._update_face(1.0 / 30.0)
		await process_frame
	head = m.boy.lie_bone_world("mixamorig_Head")
	await _shot(m, vp, "face_cheer", head, m.face_yaw + PI, 0.05, 0.72)
	# Sleep face on lounger
	m._begin_rest("sun")
	m.rest_phase = 4
	m.rest_t = 1.0
	m.set_meta("lie_snapped", false)
	for _p in 25:
		m.boy.clear_foot_plant()
		pl = m.boy.activity("sun", 1.0, 1.0, m.gt)
		m.boy.global_transform = Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
		m._snap_lie_contact()
		m._plant_lie_feet()
		await process_frame
	m.set_meta("lie_snapped", true)
	m.boy.set_face_expr("sleep")
	for _i in 8:
		m.boy._update_face(1.0 / 30.0)
		await process_frame
	head = m.boy.lie_bone_world("mixamorig_Head")
	await _shot(m, vp, "face_sleep", head, atan2(m.rest_side.x, m.rest_side.z) + 0.35, 0.12, 0.85)
	m._wake()
	m.mode = m.Mode.EXPLORE
	m.boy.end_activity()

	# --- Walk / run filmstrip (side view) ---
	m._place(Vector3(4, 0, -8), 0.0)
	m.boy.set_move(1.15)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3(0, 0, 0)
	var strip := Image.create(390 * 4, 844, false, Image.FORMAT_RGBA8)
	for f in 4:
		m.boy.phase = float(f) / 4.0
		m.boy._tick(0.05)
		var wt: Vector3 = m.player.global_position + Vector3(0, 0.65, 0)
		m.demo_cam = true
		m.demo_track = []
		m.cam_fixed = true
		m.cam_target = wt
		m.cam_yaw = PI * 0.5
		m.cam_pitch = 0.05
		m.cam_dist = 2.8
		m._apply_camera()
		for _i in 4:
			m._apply_camera()
			await process_frame
		var img: Image = vp.get_texture().get_image()
		strip.blit_rect(img, Rect2i(0, 0, 390, 844), Vector2i(f * 390, 0))
	strip.save_png("/workspace/screenshots/v24/walk_filmstrip.png")
	print("SHOT /workspace/screenshots/v24/walk_filmstrip.png")
	m.boy.set_move(2.0)
	var rstrip := Image.create(390 * 4, 844, false, Image.FORMAT_RGBA8)
	for f in 4:
		m.boy.phase = float(f) / 4.0
		m.boy._tick(0.04)
		var wt2: Vector3 = m.player.global_position + Vector3(0, 0.65, 0)
		m.cam_target = wt2
		m.cam_yaw = PI * 0.5
		m.cam_pitch = 0.05
		m.cam_dist = 2.8
		m._apply_camera()
		for _i in 4:
			m._apply_camera()
			await process_frame
		var img2: Image = vp.get_texture().get_image()
		rstrip.blit_rect(img2, Rect2i(0, 0, 390, 844), Vector2i(f * 390, 0))
	rstrip.save_png("/workspace/screenshots/v24/run_filmstrip.png")
	print("SHOT /workspace/screenshots/v24/run_filmstrip.png")

	quit(0)


func _shot(m, vp, name: String, target: Vector3, yaw: float, pitch: float, dist: float) -> void:
	m.demo_cam = true
	m.demo_track = []
	m.cam_fixed = true
	m.fix_target = target
	m.fix_yaw = yaw
	m.fix_pitch = pitch
	m.fix_dist = dist
	m.cam_target = target
	m.cam_yaw = yaw
	m.cam_pitch = pitch
	m.cam_dist = dist
	m._apply_camera()
	for _i in 8:
		if m.zzz and is_instance_valid(m.zzz):
			m.zzz.visible = false
		m.cam_target = target
		m.cam_yaw = yaw
		m.cam_pitch = pitch
		m.cam_dist = dist
		m._apply_camera()
		await process_frame
	await _shot_raw(vp, name)


func _shot_raw(vp, name: String) -> void:
	var path := "/workspace/screenshots/v24/%s.png" % name
	vp.get_texture().get_image().save_png(path)
	print("SHOT ", path)
