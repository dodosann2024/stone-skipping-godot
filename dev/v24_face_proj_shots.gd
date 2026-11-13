extends SceneTree
## Large front + 3/4 close-ups of sleep (closed-eye albedo) and blink.
## Usage: xvfb-run -a godot --path . --script res://dev/v24_face_proj_shots.gd

const OUT := "/workspace/screenshots/v24"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(780, 1200))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(780, 1200)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for _i in 40:
		await process_frame
	m.demo_mode = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	m.rest_frozen = true
	m._place(Vector3(1.5, 0, -5.5), PI)
	m.boy.set_idle()
	m.demo_cam = true
	m.demo_track = []
	m.cam_fixed = true
	# Hide island for clean face plates
	if m.island:
		m.island.visible = false
	# Force reload sleep albedo from disk
	m.boy._boy_albedo_tex_sleep = null
	m.boy._ensure_sleep_eye_albedo()
	m.boy._ensure_eyes_closed_morph()
	print("sleep_tex", m.boy._boy_albedo_tex_sleep != null, "morph_bs", m.boy._eyes_closed_bs)

	var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	# face_yaw + PI looks at the face
	var front_yaw: float = m.face_yaw + PI
	var yaw_34: float = front_yaw + 0.55

	# ---- SLEEP ----
	m.boy.set_face_expr("sleep")
	m.boy.act_kind = "sleep"
	m.boy.act_lie_k = 1.0
	for _i in 8:
		m.boy._update_face(0.05)
		await process_frame
	head = m.boy.lie_bone_world("mixamorig_Head")
	await _face(m, vp, "face_sleep_front", head, front_yaw, 0.06, 0.62)
	await _face(m, vp, "face_sleep_34", head, yaw_34, 0.10, 0.68)

	# ---- BLINK (morph mid-close + sleep albedo) ----
	m.boy.set_face_expr("neutral")
	m.boy.act_kind = "idle"
	m.boy.act_lie_k = 0.0
	m.boy.blink_timer = 99.0
	m.boy.blink_t = 0.05
	for _i in 6:
		m.boy.blink_t = 0.05
		m.boy._update_face(0.02)
		m.boy.blink_t = 0.05
		m.boy._set_eyes_closed_morph(1.0)
		m.boy._set_eyes_closed(true)
		await process_frame
	head = m.boy.lie_bone_world("mixamorig_Head")
	await _face(m, vp, "face_blink_front", head, front_yaw, 0.06, 0.62)
	await _face(m, vp, "face_blink_34", head, yaw_34, 0.10, 0.68)

	# ---- OPEN reference ----
	m.boy.blink_t = -1.0
	m.boy._set_eyes_closed(false)
	m.boy._set_eyes_closed_morph(0.0)
	for _i in 6:
		m.boy._update_face(0.05)
		await process_frame
	await _face(m, vp, "face_open_front", head, front_yaw, 0.06, 0.62)

	print("FACE_PROJ_SHOTS_DONE")
	quit(0)


func _face(m, vp: Viewport, name: String, head: Vector3, yaw: float, pitch: float, dist: float) -> void:
	m.cam_target = head + Vector3(0, 0.02, 0)
	m.cam_yaw = yaw
	m.cam_pitch = pitch
	m.cam_dist = dist
	m._apply_camera()
	var want_closed := name.begins_with("face_sleep") or name.begins_with("face_blink")
	for _i in 8:
		if want_closed:
			if name.begins_with("face_sleep"):
				m.boy.set_face_expr("sleep")
				m.boy.act_kind = "sleep"
				m.boy.act_lie_k = 1.0
				m.boy._set_eyes_closed_morph(1.0)
				m.boy._set_eyes_closed(true)
			else:
				m.boy.blink_t = 0.05
				m.boy._set_eyes_closed_morph(1.0)
				m.boy._set_eyes_closed(true)
			m.boy._update_face(0.02)
			if name.begins_with("face_blink"):
				m.boy.blink_t = 0.05
				m.boy._set_eyes_closed_morph(1.0)
				m.boy._set_eyes_closed(true)
		else:
			m.boy.blink_t = -1.0
			m.boy.set_face_expr("neutral")
			m.boy._set_eyes_closed_morph(0.0)
			m.boy._update_face(0.05)
		m._apply_camera()
		await process_frame
	# CPU bake so llvmpipe stills include the eyes_closed morph deltas.
	m.boy.bake_pose_mesh()
	await process_frame
	await process_frame
	vp.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	m.boy.restore_pose_mesh()
	print("SHOT", name, "morph_w", m.boy._eyes_closed_w)
