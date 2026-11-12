extends SceneTree
## Force sun/hammock lie, print contact gaps, save multi-angle screenshots.

func _initialize() -> void:
	call_deferred("_go")

func _go() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	for i in 40:
		await process_frame
	m._start_audio()
	m.demo_mode = true
	_clear(m)
	DirAccess.make_dir_absolute("/workspace/screenshots/v23")

	await _shot_lie(m, vp, "sun", "lounger")
	await _shot_lie(m, vp, "sleep", "hammock")
	print("LIE_CONTACT_DONE")
	quit(0)

func _clear(m) -> void:
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
		m.start_overlay = null
	m.audio_started = true
	if m.ui_root:
		m.ui_root.visible = false
	if m.tip_box:
		m.tip_box.visible = false
	if m.lbl_toast:
		m.lbl_toast.modulate.a = 0.0
	if m.zzz and is_instance_valid(m.zzz):
		m.zzz.scale = Vector3.ZERO
		m.zzz.visible = false

func _force(m, kind: String) -> void:
	m.boy.end_activity()
	m.mode = m.Mode.EXPLORE
	m.rest_phase = 0
	m.seat_lying = false
	m.zzz.visible = false
	if kind == "sun":
		var ap: Vector3 = m.island.seats[0]["approach"] if false else Vector3.ZERO
		for st in m.island.seats:
			if st["name"] == "躺椅":
				ap = st["approach"]
				break
		m._place(ap, 0.0)
	else:
		var hs: Array = m._hammock_spot()
		m._place(hs[0] + hs[2] * 1.2, atan2(-hs[2].x, -hs[2].z))
	await m.get_tree().create_timer(0.1).timeout
	m._begin_rest(kind)
	m.rest_phase = 4
	m.rest_t = 0.1
	m.swing_amp = 0.04 if kind == "sleep" else 0.0
	m.set_meta("lie_snapped", false)
	_clear(m)
	for i in 20:
		var pl: Vector3 = m.boy.activity(kind, 1.0, 1.0, m.gt)
		var swing := Transform3D.IDENTITY
		if kind == "sleep":
			swing = m.island.swing_hammock(m.swing_amp * sin(m.gt * 1.3))
		m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
		if i == 2 and not m.get_meta("lie_snapped", false):
			for _p in 2:
				m._snap_lie_contact()
				pl = m.boy.activity(kind, 1.0, 1.0, m.gt)
				swing = Transform3D.IDENTITY
				if kind == "sleep":
					swing = m.island.swing_hammock(m.swing_amp * sin(m.gt * 1.3))
				m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl)
			m.set_meta("lie_snapped", true)
		m.gt += 1.0 / 30.0
		await m.get_tree().process_frame

func _shot_lie(m, vp: Viewport, kind: String, tag: String) -> void:
	await _force(m, kind)
	_clear(m)
	var gaps: Dictionary = m.lie_contact_gaps()
	print("GAPS ", tag, " ", gaps)
	var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	var foot: Vector3 = m.boy.lie_bone_world("mixamorig_LeftFoot")
	print("BONES ", tag, " hips", hips, " head", head, " foot", foot)
	var side: Vector3 = m.rest_side.normalized()
	var mid: Vector3 = (hips + head + foot) / 3.0

	# side view
	m.cam_target = mid
	m.cam_yaw = atan2(side.x, side.z)
	m.cam_pitch = 0.12
	m.cam_dist = 2.7
	m._apply_camera()
	for i in 8:
		await m.get_tree().process_frame
	_clear(m)
	_save(vp, "/workspace/screenshots/v23/%s_side.png" % tag)

	# 3/4 view
	m.cam_yaw = atan2(side.x, side.z) + 0.55
	m.cam_pitch = 0.28
	m.cam_dist = 2.9
	m._apply_camera()
	for i in 8:
		await m.get_tree().process_frame
	_clear(m)
	_save(vp, "/workspace/screenshots/v23/%s_34.png" % tag)

	m.boy.end_activity()
	m.mode = m.Mode.EXPLORE
	m.rest_phase = 0
	await m.get_tree().create_timer(0.2).timeout

func _save(vp: Viewport, path: String) -> void:
	var img: Image = vp.get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())
